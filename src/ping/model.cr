module Ping
  struct SampleInput
    getter recorded_at : Time
    getter sequence : Int32?
    getter raw_line : String
    getter? success : Bool
    getter rtt_ms : Float64?
    getter category : Symbol

    def initialize(
      @recorded_at : Time,
      @sequence : Int32?,
      @raw_line : String,
      @success : Bool,
      @rtt_ms : Float64?,
      @category : Symbol,
    )
    end
  end

  struct Sample
    getter session_id : Int64
    getter recorded_at : Time
    getter sequence : Int32?
    getter raw_line : String
    getter? success : Bool
    getter rtt_ms : Float64?
    getter category : Symbol
    getter failure_streak : Int32

    def initialize(
      @session_id : Int64,
      @recorded_at : Time,
      @sequence : Int32?,
      @raw_line : String,
      @success : Bool,
      @rtt_ms : Float64?,
      @category : Symbol,
      @failure_streak : Int32,
    )
    end
  end

  struct MonitoringSession
    getter id : Int64
    getter host : String
    getter instance_id : String
    getter started_at : Time
    getter ended_at : Time?

    def initialize(
      @id : Int64,
      @host : String,
      @instance_id : String,
      @started_at : Time,
      @ended_at : Time?,
    )
    end
  end

  struct ChartRow
    getter label : String
    getter window : Time::Span?
    getter major_tick_interval : Time::Span
    getter minor_tick_interval : Time::Span

    def initialize(@label : String, @window : Time::Span?, @major_tick_interval : Time::Span, @minor_tick_interval : Time::Span)
    end
  end

  struct RowSeries
    getter states : Array(Int32?)

    def initialize(@states : Array(Int32?))
    end
  end
end
