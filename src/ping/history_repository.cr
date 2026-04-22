require "db"
require "sqlite3"

module Ping
  class HistoryRepository
    BUSY_TIMEOUT_MS = 5_000

    @db : DB::Database

    def initialize(@path : String = Settings.history_db_path)
      Dir.mkdir_p(File.dirname(@path))
      @db = DB.open("sqlite3:#{@path}")
      configure_connection
      migrate
    end

    def close : Nil
      @db.close
    end

    def create_session(host : String, instance_id : String, started_at : Time) : MonitoringSession
      result = @db.exec(
        <<-SQL,
          INSERT INTO monitoring_sessions (
            host,
            instance_id,
            started_at_unix_ms,
            started_at_iso
          ) VALUES (?, ?, ?, ?)
          SQL
        host,
        instance_id,
        started_at.to_unix_ms,
        started_at.to_s("%Y-%m-%dT%H:%M:%S%:z"),
      )

      MonitoringSession.new(result.last_insert_id, host, instance_id, started_at, nil)
    end

    def close_session(session_id : Int64, ended_at : Time) : Nil
      @db.exec(
        <<-SQL,
          UPDATE monitoring_sessions
          SET ended_at_unix_ms = ?, ended_at_iso = ?
          WHERE id = ?
          SQL
        ended_at.to_unix_ms,
        ended_at.to_s("%Y-%m-%dT%H:%M:%S%:z"),
        session_id,
      )
    end

    def save_sample(session_id : Int64, sample : Sample) : Nil
      @db.exec(
        <<-SQL,
          INSERT INTO samples (
            session_id,
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
        session_id,
        sample.recorded_at.to_unix_ms,
        sample.recorded_at.to_s("%Y-%m-%dT%H:%M:%S%:z"),
        sample.sequence,
        sample.raw_line,
        sample.success? ? 1 : 0,
        sample.rtt_ms,
        sample.category.to_s,
        sample.failure_streak
      )
    end

    def load_history(host : String, since : Time? = nil, until_time : Time? = nil) : {Array(MonitoringSession), Array(Sample)}
      {load_sessions(host, since, until_time), load_samples(host, since, until_time)}
    end

    def load_sessions(host : String, since : Time? = nil, until_time : Time? = nil) : Array(MonitoringSession)
      sessions = [] of MonitoringSession
      if since && until_time
        @db.query(
          <<-SQL,
            SELECT id, host, instance_id, started_at_unix_ms, ended_at_unix_ms
            FROM monitoring_sessions
            WHERE host = ?
              AND started_at_unix_ms < ?
              AND (ended_at_unix_ms IS NULL OR ended_at_unix_ms >= ?)
            ORDER BY started_at_unix_ms ASC
            SQL
          host,
          until_time.to_unix_ms,
          since.to_unix_ms,
        ) do |result_set|
          read_sessions(result_set, sessions)
        end
      elsif since
        @db.query(
          <<-SQL,
            SELECT id, host, instance_id, started_at_unix_ms, ended_at_unix_ms
            FROM monitoring_sessions
            WHERE host = ?
              AND (ended_at_unix_ms IS NULL OR ended_at_unix_ms >= ?)
            ORDER BY started_at_unix_ms ASC
            SQL
          host,
          since.to_unix_ms,
        ) do |result_set|
          read_sessions(result_set, sessions)
        end
      elsif until_time
        @db.query(
          <<-SQL,
            SELECT id, host, instance_id, started_at_unix_ms, ended_at_unix_ms
            FROM monitoring_sessions
            WHERE host = ?
              AND started_at_unix_ms < ?
            ORDER BY started_at_unix_ms ASC
            SQL
          host,
          until_time.to_unix_ms,
        ) do |result_set|
          read_sessions(result_set, sessions)
        end
      else
        @db.query(
          <<-SQL,
            SELECT id, host, instance_id, started_at_unix_ms, ended_at_unix_ms
            FROM monitoring_sessions
            WHERE host = ?
            ORDER BY started_at_unix_ms ASC
            SQL
          host,
        ) do |result_set|
          read_sessions(result_set, sessions)
        end
      end
      sessions
    end

    def load_samples(host : String, since : Time? = nil, until_time : Time? = nil) : Array(Sample)
      samples = [] of Sample
      if since && until_time
        @db.query(
          <<-SQL,
            SELECT samples.session_id, samples.recorded_at_unix_ms, samples.sequence, samples.raw_line,
                   samples.success, samples.rtt_ms, samples.category, samples.failure_streak
            FROM samples
            INNER JOIN monitoring_sessions ON monitoring_sessions.id = samples.session_id
            WHERE monitoring_sessions.host = ?
              AND samples.recorded_at_unix_ms >= ?
              AND samples.recorded_at_unix_ms < ?
            ORDER BY samples.recorded_at_unix_ms ASC
            SQL
          host,
          since.to_unix_ms,
          until_time.to_unix_ms
        ) do |result_set|
          read_rows(result_set, samples)
        end
      elsif since
        @db.query(
          <<-SQL,
            SELECT samples.session_id, samples.recorded_at_unix_ms, samples.sequence, samples.raw_line,
              samples.success, samples.rtt_ms, samples.category, samples.failure_streak
            FROM samples
            INNER JOIN monitoring_sessions ON monitoring_sessions.id = samples.session_id
            WHERE monitoring_sessions.host = ? AND samples.recorded_at_unix_ms >= ?
            ORDER BY samples.recorded_at_unix_ms ASC
            SQL
          host,
          since.to_unix_ms
        ) do |result_set|
          read_rows(result_set, samples)
        end
      elsif until_time
        @db.query(
          <<-SQL,
            SELECT samples.session_id, samples.recorded_at_unix_ms, samples.sequence, samples.raw_line,
                   samples.success, samples.rtt_ms, samples.category, samples.failure_streak
            FROM samples
            INNER JOIN monitoring_sessions ON monitoring_sessions.id = samples.session_id
            WHERE monitoring_sessions.host = ?
              AND samples.recorded_at_unix_ms < ?
            ORDER BY samples.recorded_at_unix_ms ASC
            SQL
          host,
          until_time.to_unix_ms
        ) do |result_set|
          read_rows(result_set, samples)
        end
      else
        @db.query(
          <<-SQL,
            SELECT samples.session_id, samples.recorded_at_unix_ms, samples.sequence, samples.raw_line,
              samples.success, samples.rtt_ms, samples.category, samples.failure_streak
            FROM samples
            INNER JOIN monitoring_sessions ON monitoring_sessions.id = samples.session_id
            WHERE monitoring_sessions.host = ?
            ORDER BY samples.recorded_at_unix_ms ASC
            SQL
          host
        ) do |result_set|
          read_rows(result_set, samples)
        end
      end
      samples
    end

    private def configure_connection : Nil
      @db.exec "PRAGMA journal_mode=WAL"
      @db.exec "PRAGMA busy_timeout=#{BUSY_TIMEOUT_MS}"
      @db.exec "PRAGMA foreign_keys=ON"
    end

    private def migrate : Nil
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS monitoring_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          host TEXT NOT NULL,
          instance_id TEXT NOT NULL,
          started_at_unix_ms INTEGER NOT NULL,
          ended_at_unix_ms INTEGER,
          started_at_iso TEXT NOT NULL,
          ended_at_iso TEXT
        )
        SQL

      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS samples (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          recorded_at_unix_ms INTEGER NOT NULL,
          recorded_at_iso TEXT NOT NULL,
          sequence INTEGER,
          raw_line TEXT NOT NULL,
          success INTEGER NOT NULL,
          rtt_ms REAL,
          category TEXT NOT NULL,
          failure_streak INTEGER NOT NULL,
          FOREIGN KEY(session_id) REFERENCES monitoring_sessions(id)
        )
        SQL

      @db.exec "CREATE INDEX IF NOT EXISTS idx_samples_recorded_at ON samples(recorded_at_unix_ms)"
      @db.exec "CREATE INDEX IF NOT EXISTS idx_samples_session_recorded_at ON samples(session_id, recorded_at_unix_ms)"
      @db.exec "CREATE INDEX IF NOT EXISTS idx_sessions_host_started_at ON monitoring_sessions(host, started_at_unix_ms)"
    end

    private def read_sessions(result_set : DB::ResultSet, sessions : Array(MonitoringSession)) : Nil
      result_set.each do
        id = result_set.read(Int64)
        host = result_set.read(String)
        instance_id = result_set.read(String)
        started_at_ms = result_set.read(Int64)
        ended_at_ms = result_set.read(Int64?)

        sessions << MonitoringSession.new(
          id,
          host,
          instance_id,
          Time.unix_ms(started_at_ms),
          ended_at_ms ? Time.unix_ms(ended_at_ms) : nil,
        )
      end
    end

    private def read_rows(result_set : DB::ResultSet, samples : Array(Sample)) : Nil
      result_set.each do
        session_id = result_set.read(Int64)
        recorded_at_ms = result_set.read(Int64)
        sequence = result_set.read(Int64?).try(&.to_i32)
        raw_line = result_set.read(String)
        success = result_set.read(Int64) == 1_i64
        rtt_ms = result_set.read(Float64?)
        category = result_set.read(String)
        failure_streak = result_set.read(Int64).to_i32

        samples << Sample.new(
          session_id,
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
