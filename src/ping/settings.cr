module Ping
  # Shared mutable settings for severity thresholds and chart colors.
  # severity levels: 0=ok, 1=warn, 2=alert, 3=critical
  class Settings
    MIN_INTERVAL_MS     = 250
    MAX_INTERVAL_MS     = 5000
    DEFAULT_INTERVAL_MS = 1000

    # Failure-streak thresholds: streak <= threshold => that level
    property warn_threshold : Int32  # streak <= this => severity 1
    property alert_threshold : Int32 # streak <= this => severity 2
    # streak >  this => severity 3

    # Colors as {r, g, b} in 0.0..1.0
    property color_ok : {Float64, Float64, Float64}
    property color_warn : {Float64, Float64, Float64}
    property color_alert : {Float64, Float64, Float64}
    property color_critical : {Float64, Float64, Float64}

    def initialize
      @warn_threshold = 2
      @alert_threshold = 5
      @color_ok = {0.20, 0.71, 0.33}
      @color_warn = {0.95, 0.83, 0.20}
      @color_alert = {0.96, 0.55, 0.15}
      @color_critical = {0.83, 0.20, 0.20}
      normalize!
    end

    def normalize! : Nil
      @warn_threshold = 1 if @warn_threshold < 1
      @alert_threshold = @warn_threshold + 1 if @alert_threshold <= @warn_threshold
    end

    def clamp_interval_ms(value : Int32) : Int32
      value.clamp(MIN_INTERVAL_MS, MAX_INTERVAL_MS)
    end

    def color_for(severity : Int32) : {Float64, Float64, Float64}
      case severity
      when 0 then @color_ok
      when 1 then @color_warn
      when 2 then @color_alert
      else        @color_critical
      end
    end
  end
end
