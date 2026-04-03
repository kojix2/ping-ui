require "json"

module Ping
  # Shared mutable settings for severity thresholds and chart colors.
  # severity levels: 0=ok, 1=warn, 2=alert, 3=critical
  class Settings
    MIN_INTERVAL_MS     =  100
    MAX_INTERVAL_MS     = 5000
    DEFAULT_INTERVAL_MS = 1000
    MAX_RECENT_HOSTS    =   10

    # Failure-streak thresholds: streak <= threshold => that level
    property warn_threshold : Int32  # streak <= this => severity 1
    property alert_threshold : Int32 # streak <= this => severity 2
    # streak >  this => severity 3

    # Colors as {r, g, b} in 0.0..1.0
    property color_ok : {Float64, Float64, Float64}
    property color_warn : {Float64, Float64, Float64}
    property color_alert : {Float64, Float64, Float64}
    property color_critical : {Float64, Float64, Float64}
    property recent_hosts : Array(String)
    property? notify_enabled : Bool
    property notify_failures_threshold : Int32

    def initialize
      @warn_threshold = 2
      @alert_threshold = 5
      @color_ok = {0.20, 0.71, 0.33}
      @color_warn = {0.95, 0.83, 0.20}
      @color_alert = {0.96, 0.55, 0.15}
      @color_critical = {0.83, 0.20, 0.20}
      @recent_hosts = [] of String
      @notify_enabled = false
      @notify_failures_threshold = 3
      normalize!
    end

    def self.settings_path : String
      File.join(config_dir, "settings.json")
    end

    def self.history_db_path : String
      File.join(config_dir, "history.sqlite3")
    end

    def self.config_dir : String
      config_home = ENV["XDG_CONFIG_HOME"]?
      if config_home && !config_home.empty?
        return File.join(config_home, "ping-ui")
      end

      home = ENV["HOME"]? || "."
      File.join(home, ".config", "ping-ui")
    end

    def self.load : Settings
      path = settings_path
      return new unless File.exists?(path)

      parsed = JSON.parse(File.read(path)).as_h
      settings = new

      settings.warn_threshold = parsed["warn_threshold"]?.try(&.as_i).try(&.to_i32) || settings.warn_threshold
      settings.alert_threshold = parsed["alert_threshold"]?.try(&.as_i).try(&.to_i32) || settings.alert_threshold
      settings.color_ok = load_color(parsed["color_ok"]?) || settings.color_ok
      settings.color_warn = load_color(parsed["color_warn"]?) || settings.color_warn
      settings.color_alert = load_color(parsed["color_alert"]?) || settings.color_alert
      settings.color_critical = load_color(parsed["color_critical"]?) || settings.color_critical
      settings.recent_hosts = load_recent_hosts(parsed["recent_hosts"]?)
      settings.notify_enabled = (parsed["notify_enabled"]?.try(&.as_bool) || false)
      settings.notify_failures_threshold = parsed["notify_failures_threshold"]?.try(&.as_i).try(&.to_i32) || settings.notify_failures_threshold
      settings.normalize!
      settings
    rescue
      new
    end

    def normalize! : Nil
      @warn_threshold = 1 if @warn_threshold < 1
      @alert_threshold = @warn_threshold + 1 if @alert_threshold <= @warn_threshold
      @notify_failures_threshold = 1 if @notify_failures_threshold < 1
    end

    def save : Nil
      path = self.class.settings_path
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      File.write(path, JSON.build { |json| to_json(json) })
    rescue
      nil
    end

    def add_recent_host(host : String) : Nil
      value = host.strip
      return if value.empty?

      @recent_hosts.reject!(&.== value)
      @recent_hosts.unshift(value)
      @recent_hosts = @recent_hosts.first(MAX_RECENT_HOSTS)
      save
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

    private def to_json(json : JSON::Builder) : Nil
      json.object do
        json.field "warn_threshold", @warn_threshold
        json.field "alert_threshold", @alert_threshold
        json.field "color_ok" do
          write_color(json, @color_ok)
        end
        json.field "color_warn" do
          write_color(json, @color_warn)
        end
        json.field "color_alert" do
          write_color(json, @color_alert)
        end
        json.field "color_critical" do
          write_color(json, @color_critical)
        end
        json.field "recent_hosts" do
          json.array do
            @recent_hosts.each { |host| json.string(host) }
          end
        end
        json.field "notify_enabled", @notify_enabled
        json.field "notify_failures_threshold", @notify_failures_threshold
      end
    end

    private def write_color(json : JSON::Builder, color : {Float64, Float64, Float64}) : Nil
      json.array do
        json.number(color[0])
        json.number(color[1])
        json.number(color[2])
      end
    end

    private def self.load_color(any : JSON::Any?) : {Float64, Float64, Float64}?
      ary = any.try(&.as_a?)
      return nil unless ary && ary.size == 3

      r = ary[0]?.try(&.as_f?)
      g = ary[1]?.try(&.as_f?)
      b = ary[2]?.try(&.as_f?)
      return nil unless r && g && b
      {r, g, b}
    end

    private def self.load_recent_hosts(any : JSON::Any?) : Array(String)
      ary = any.try(&.as_a?)
      return [] of String unless ary

      hosts = [] of String
      ary.each do |v|
        next unless text = v.as_s?
        text = text.strip
        next if text.empty?
        hosts << text
      end
      hosts.uniq.first(MAX_RECENT_HOSTS)
    end
  end
end
