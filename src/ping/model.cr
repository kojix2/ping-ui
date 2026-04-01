module Ping
  struct SampleInput
    getter recorded_at : Time
    getter sequence : Int32?
    getter raw_line : String
    getter success : Bool
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
    getter recorded_at : Time
    getter sequence : Int32?
    getter raw_line : String
    getter success : Bool
    getter rtt_ms : Float64?
    getter category : Symbol
    getter failure_streak : Int32

    def initialize(
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

  struct ChartRow
    getter label : String
    getter window : Time::Span?

    def initialize(@label : String, @window : Time::Span?)
    end
  end

  struct RowSeries
    getter states : Array(Int32?)
    getter latency : Array(Float64?)
    getter latency_scale_ms : Float64

    def initialize(@states : Array(Int32?), @latency : Array(Float64?), @latency_scale_ms : Float64)
    end
  end
end
