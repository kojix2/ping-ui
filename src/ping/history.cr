module Ping
  class HistoryStore
    MIN_RTT_SCALE_MS = 20.0

    getter samples : Array(Sample)

    def initialize(@settings : Settings)
      @samples = [] of Sample
      @current_failure_streak = 0
    end

    def clear : Nil
      @samples.clear
      @current_failure_streak = 0
    end

    def add(input : SampleInput) : Sample
      if input.success
        @current_failure_streak = 0
      else
        @current_failure_streak += 1
      end

      sample = Sample.new(
        input.recorded_at,
        input.sequence,
        input.raw_line,
        input.success,
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
      latency = Array(Float64?).new(n, nil)
      return RowSeries.new(states, latency, MIN_RTT_SCALE_MS) if @samples.empty?

      from_ms, span_ms = window_bounds(window, now)
      fill_until_ms = (fill_until || now).to_unix_ms
      fill_until_ms = from_ms if fill_until_ms < from_ms
      fill_until_ms = from_ms + span_ms if fill_until_ms > from_ms + span_ms
      col_width = span_ms.to_f / n
      col_width = 1.0 if col_width < 1.0

      relevant = @samples.select { |s|
        ms = s.recorded_at.to_unix_ms
        ms >= from_ms && ms <= fill_until_ms
      }
      return RowSeries.new(states, latency, MIN_RTT_SCALE_MS) if relevant.empty?

      relevant.each_with_index do |sample, idx|
        col_start = ((sample.recorded_at.to_unix_ms - from_ms) / col_width).floor.to_i
        col_start = col_start.clamp(0, n - 1)

        # Fill forward until just before the next sample (or end of chart for last sample)
        col_end = if idx + 1 < relevant.size
                    nxt_ms = relevant[idx + 1].recorded_at.to_unix_ms
                    capped_ms = nxt_ms > fill_until_ms ? fill_until_ms : nxt_ms
                    nxt_col = ((capped_ms - from_ms) / col_width).floor.to_i - 1
                    nxt_col.clamp(col_start, n - 1)
                  else
                    last_col = ((fill_until_ms - from_ms) / col_width).floor.to_i
                    last_col.clamp(col_start, n - 1)
                  end

        sev = severity_of(sample)
        col_start.upto(col_end) { |c| states[c] = sev }

        if sample.success && (rtt = sample.rtt_ms)
          latency[col_start] = rtt
        end
      end

      rtt_values = latency.compact
      p95 = percentile(rtt_values, 0.95)
      scale = Math.max(MIN_RTT_SCALE_MS, p95 * 1.1)
      RowSeries.new(states, latency, scale)
    end

    private def severity_of(s : Sample) : Int32
      return 0 if s.success
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

      first_ms = @samples.first.recorded_at.to_unix_ms
      span_ms = now_ms - first_ms
      span_ms = 1_i64 if span_ms <= 0
      {first_ms, span_ms}
    end

    private def percentile(values : Array(Float64), q : Float64) : Float64
      return 0.0 if values.empty?

      sorted = values.sort
      pos = (sorted.size * q).ceil.to_i - 1
      idx = pos.clamp(0, sorted.size - 1)
      sorted[idx]
    end
  end
end
