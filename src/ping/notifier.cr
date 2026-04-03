module Ping
  class Notifier
    @notified_for_current_outage : Bool

    def initialize(@settings : Settings)
      @notified_for_current_outage = false
    end

    def reset : Nil
      @notified_for_current_outage = false
    end

    def maybe_notify(host : String, sample : Sample) : Nil
      if sample.success?
        @notified_for_current_outage = false
        return
      end

      return unless @settings.notify_enabled?
      return unless sample.failure_streak >= @settings.notify_failures_threshold
      return if @notified_for_current_outage

      @notified_for_current_outage = send_notification(host, sample.failure_streak)
    end

    private def send_notification(host : String, streak : Int32) : Bool
      message = "#{host}: #{streak} consecutive failures"
      title = "Ping UI Alert"

      {% if flag?(:darwin) %}
        script = "display notification #{message.inspect} with title #{title.inspect}"
        status = Process.run("osascript", args: ["-e", script], output: Process::Redirect::Close, error: Process::Redirect::Close)
        return status.success?
      {% elsif flag?(:linux) %}
        notify_send = Process.find_executable("notify-send")
        return false unless notify_send

        status = Process.run(notify_send, args: [title, message], output: Process::Redirect::Close, error: Process::Redirect::Close)
        return status.success?
      {% else %}
        false
      {% end %}
    rescue
      false
    end
  end
end
