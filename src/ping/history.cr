module Ping
  class HistoryStore
    getter samples : Array(Sample)
    getter sessions : Array(MonitoringSession)

    def initialize(@settings : Settings)
      @sessions = [] of MonitoringSession
      @samples = [] of Sample
      @live_session_id = nil.as(Int64?)
      @current_failure_streak = 0
    end

    def clear : Nil
      @sessions.clear
      @samples.clear
      @live_session_id = nil
      @current_failure_streak = 0
    end

    def replace(sessions : Array(MonitoringSession), samples : Array(Sample)) : Nil
      @sessions = sessions
      @samples = samples
      @live_session_id = nil
      last = @samples.last?
      @current_failure_streak = if last && !last.success?
                                  last.failure_streak
                                else
                                  0
                                end
    end

    def start_session(session : MonitoringSession) : Nil
      @sessions << session
      @live_session_id = session.id if session.ended_at.nil?
      @current_failure_streak = 0
    end

    def finish_session(session_id : Int64, ended_at : Time) : Nil
      if index = @sessions.index { |session| session.id == session_id }
        session = @sessions[index]
        @sessions[index] = MonitoringSession.new(
          session.id,
          session.host,
          session.instance_id,
          session.started_at,
          ended_at,
        )
      end
      @live_session_id = nil if @live_session_id == session_id
    end

    def add(input : SampleInput, session_id : Int64) : Sample
      if input.success?
        @current_failure_streak = 0
      else
        @current_failure_streak += 1
      end

      sample = Sample.new(
        session_id,
        input.recorded_at,
        input.sequence,
        input.raw_line,
        input.success?,
        input.rtt_ms,
        input.category,
        @current_failure_streak
      )
      @samples << sample
      sample
    end

    def latest_sample : Sample?
      @samples.last?
    end

    def row_series(window : Time::Span?, columns : Int32, now : Time = Time.local, fill_until : Time? = nil) : RowSeries
      n = [columns, 1].max
      states = Array(Int32?).new(n, nil)
      return RowSeries.new(states) if @samples.empty? && @sessions.empty?

      from_ms, span_ms = window_bounds(window, now)
      fill_until_ms = (fill_until || now).to_unix_ms
      fill_until_ms = from_ms if fill_until_ms < from_ms
      fill_until_ms = from_ms + span_ms if fill_until_ms > from_ms + span_ms
      col_width = span_ms.to_f / n
      col_width = 1.0 if col_width < 1.0

      relevant = @samples.select { |sample|
        ms = sample.recorded_at.to_unix_ms
        ms >= from_ms && ms <= fill_until_ms
      }
      samples_by_session = relevant.group_by(&.session_id)
      last_sample_ms_by_session = build_last_sample_ms_by_session(samples_by_session)

      apply_sessions(states, samples_by_session, last_sample_ms_by_session, from_ms, span_ms, fill_until_ms, col_width, n)

      RowSeries.new(states)
    end

    private def apply_sessions(states : Array(Int32?), samples_by_session : Hash(Int64, Array(Sample)), last_sample_ms_by_session : Hash(Int64, Int64), from_ms : Int64, span_ms : Int64, fill_until_ms : Int64, col_width : Float64, columns : Int32) : Nil
      @sessions.each do |session|
        session_end_ms = effective_session_end_ms(session, fill_until_ms, last_sample_ms_by_session)
        next unless session_end_ms

        session_start_ms = session.started_at.to_unix_ms
        next if session_end_ms <= from_ms
        next if session_start_ms >= from_ms + span_ms

        session_samples = samples_by_session[session.id]? || [] of Sample
        apply_session_samples(states, session_samples, from_ms, session_end_ms, col_width, columns)
      end
    end

    private def build_last_sample_ms_by_session(samples_by_session : Hash(Int64, Array(Sample))) : Hash(Int64, Int64)
      last_sample_ms_by_session = {} of Int64 => Int64
      samples_by_session.each do |session_id, samples|
        last_sample = samples.last?
        next unless last_sample

        last_sample_ms_by_session[session_id] = last_sample.recorded_at.to_unix_ms
      end
      last_sample_ms_by_session
    end

    private def apply_session_samples(states : Array(Int32?), samples : Array(Sample), from_ms : Int64, session_end_ms : Int64, col_width : Float64, columns : Int32) : Nil
      return if samples.empty?

      samples.each_with_index do |sample, idx|
        col_start = ((sample.recorded_at.to_unix_ms - from_ms) / col_width).floor.to_i
        col_start = col_start.clamp(0, columns - 1)

        col_end = if idx + 1 < samples.size
                    nxt_ms = samples[idx + 1].recorded_at.to_unix_ms
                    capped_ms = nxt_ms > session_end_ms ? session_end_ms : nxt_ms
                    nxt_col = ((capped_ms - from_ms) / col_width).floor.to_i - 1
                    nxt_col.clamp(col_start, columns - 1)
                  else
                    last_fill_ms = session_end_ms - 1
                    last_col = ((last_fill_ms - from_ms) / col_width).floor.to_i
                    last_col.clamp(col_start, columns - 1)
                  end

        sev = severity_of(sample)
        col_start.upto(col_end) { |col| states[col] = sev }
      end
    end

    # Open sessions from a previous crashed run are not treated as live.
    # Their effective end is capped at the last persisted sample, after which the chart is blank.
    private def effective_session_end_ms(session : MonitoringSession, fill_until_ms : Int64, last_sample_ms_by_session : Hash(Int64, Int64)) : Int64?
      if ended_at = session.ended_at
        ended_at_ms = ended_at.to_unix_ms
        return ended_at_ms > fill_until_ms ? fill_until_ms : ended_at_ms
      end

      return fill_until_ms if @live_session_id == session.id

      last_sample_ms_by_session[session.id]?
    end

    private def severity_of(s : Sample) : Int32
      return 0 if s.success?
      streak = s.failure_streak
      return 1 if streak <= @settings.warn_threshold
      return 2 if streak <= @settings.alert_threshold
      3
    end

    private def window_bounds(window : Time::Span?, now : Time) : {Int64, Int64}
      now_ms = now.to_unix_ms

      if window
        span_ms = window.total_milliseconds.to_i64
        span_ms = 1_i64 if span_ms <= 0
        return {now_ms - span_ms, span_ms}
      end

      first_session_ms = @sessions.first?.try(&.started_at.to_unix_ms)
      first_sample_ms = @samples.first?.try(&.recorded_at.to_unix_ms)
      first_ms = first_session_ms || first_sample_ms || now_ms
      if first_sample_ms && first_sample_ms < first_ms
        first_ms = first_sample_ms
      end
      span_ms = now_ms - first_ms
      span_ms = 1_i64 if span_ms <= 0
      {first_ms, span_ms}
    end
  end
end
