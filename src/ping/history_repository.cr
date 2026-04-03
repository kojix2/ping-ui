require "db"
require "sqlite3"

module Ping
  class HistoryRepository
    @db : DB::Database

    def initialize(@path : String = Settings.history_db_path)
      Dir.mkdir_p(File.dirname(@path))
      @db = DB.open("sqlite3:#{@path}")
      migrate
    end

    def close : Nil
      @db.close
    end

    def save_sample(host : String, sample : Sample) : Nil
      @db.exec(
        <<-SQL,
        INSERT INTO samples (
          host,
          recorded_at_unix_ms,
          recorded_at_iso,
          sequence,
          raw_line,
          success,
          rtt_ms,
          category,
          failure_streak
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        host,
        sample.recorded_at.to_unix_ms,
        sample.recorded_at.to_s("%Y-%m-%dT%H:%M:%S%:z"),
        sample.sequence,
        sample.raw_line,
        sample.success ? 1 : 0,
        sample.rtt_ms,
        sample.category.to_s,
        sample.failure_streak
      )
    end

    def load_samples(host : String, since : Time? = nil) : Array(Sample)
      samples = [] of Sample
      if since
        @db.query(
          <<-SQL,
          SELECT recorded_at_unix_ms, sequence, raw_line, success, rtt_ms, category, failure_streak
          FROM samples
          WHERE host = ? AND recorded_at_unix_ms >= ?
          ORDER BY recorded_at_unix_ms ASC
          SQL
          host,
          since.to_unix_ms
        ) do |rs|
          read_rows(rs, samples)
        end
      else
        @db.query(
          <<-SQL,
          SELECT recorded_at_unix_ms, sequence, raw_line, success, rtt_ms, category, failure_streak
          FROM samples
          WHERE host = ?
          ORDER BY recorded_at_unix_ms ASC
          SQL
          host
        ) do |rs|
          read_rows(rs, samples)
        end
      end
      samples
    end

    private def migrate : Nil
      @db.exec <<-SQL
      CREATE TABLE IF NOT EXISTS samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        host TEXT NOT NULL,
        recorded_at_unix_ms INTEGER NOT NULL,
        recorded_at_iso TEXT NOT NULL,
        sequence INTEGER,
        raw_line TEXT NOT NULL,
        success INTEGER NOT NULL,
        rtt_ms REAL,
        category TEXT NOT NULL,
        failure_streak INTEGER NOT NULL
      )
      SQL

      @db.exec "CREATE INDEX IF NOT EXISTS idx_samples_recorded_at ON samples(recorded_at_unix_ms)"
      @db.exec "CREATE INDEX IF NOT EXISTS idx_samples_host_recorded_at ON samples(host, recorded_at_unix_ms)"
    end

    private def read_rows(rs : DB::ResultSet, samples : Array(Sample)) : Nil
      rs.each do
        recorded_at_ms = rs.read(Int64)
        sequence = rs.read(Int64?).try(&.to_i32)
        raw_line = rs.read(String)
        success = rs.read(Int64) == 1_i64
        rtt_ms = rs.read(Float64?)
        category = rs.read(String)
        failure_streak = rs.read(Int64).to_i32

        samples << Sample.new(
          Time.unix_ms(recorded_at_ms),
          sequence,
          raw_line,
          success,
          rtt_ms,
          parse_category(category),
          failure_streak
        )
      end
    end

    private def parse_category(value : String) : Symbol
      case value
      when "success" then :success
      when "timeout" then :timeout
      when "failure" then :failure
      else
        :failure
      end
    end
  end
end
