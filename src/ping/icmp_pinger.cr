require "socket"

module Ping
  # Native Crystal ICMP ping using SOCK_DGRAM + IPPROTO_ICMP.
  # On macOS regular users can open ICMP datagram sockets without root.
  # Each ping session runs in a dedicated OS thread (Fiber::ExecutionContext::Isolated)
  # so it doesn't block the UIng event loop on the main thread.
  class ICMPPinger
    PAYLOAD          = "CrystalPingMon  " # exactly 16 bytes
    DEFAULT_INTERVAL = 1.second
    TIMEOUT          = 2.seconds

    struct FixedPeriodSchedule
      getter next_send_at : Time::Instant

      def initialize(started_at : Time::Instant, @interval : Time::Span)
        @next_send_at = started_at
      end

      def remaining(now : Time::Instant) : Time::Span
        wait = @next_send_at - now
        wait.positive? ? wait : Time::Span.zero
      end

      def mark_sent : Nil
        @next_send_at += @interval
      end
    end

    @running : Bool
    @sequence : UInt32
    @ping_thread : Thread?

    def initialize(
      @on_log : Proc(String, Nil),
      @on_sample : Proc(SampleInput, Nil),
      @on_finished : Proc(String?, Nil),
      @interval : Time::Span = DEFAULT_INTERVAL,
    )
      @running = false
      @sequence = 0_u32
    end

    def running? : Bool
      @running
    end

    def self.start_error_message(message : String?) : String?
      return message unless message

      normalized = message.downcase
      return message unless normalized.includes?("operation not permitted") || normalized.includes?("permission denied")

      "ICMP socket permission denied: #{message}. On Linux, grant CAP_NET_RAW to the binary with 'setcap cap_net_raw=+ep ./bin/ping' or run with sufficient privileges."
    end

    def start(host : String) : Nil
      raise "already running" if @running
      @running = true
      # Run the ping loop on a dedicated OS thread so it doesn't block
      # the UIng event loop which occupies the main thread.
      @ping_thread = Thread.new { run_loop(host) }
    end

    def stop : Nil
      @running = false
    end

    private def run_loop(host : String) : Nil
      resolved = resolve(host)
      unless resolved
        finish("Cannot resolve: #{host}")
        return
      end

      @on_log.call("PING #{host} (#{resolved}): #{PAYLOAD.bytesize} data bytes")
      schedule = FixedPeriodSchedule.new(Time.instant, @interval)

      {% if flag?(:win32) %}
        run_windows_loop(resolved, schedule)
      {% else %}
        run_socket_loop(resolved, schedule)
      {% end %}

      finish(nil)
    rescue ex
      finish(self.class.start_error_message(ex.message))
    end

    private def sleep_until(wait : Time::Span) : Nil
      sleep(wait) if wait.positive? && @running
    end

    private def finish(message : String?) : Nil
      @running = false
      @on_finished.call(message)
    end

    private def resolve(host : String) : String?
      # Already an IPv4 address?
      return host if host.matches?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
      # DNS lookup
      infos = Socket::Addrinfo.resolve(host, "0", Socket::Family::INET, Socket::Type::DGRAM)
      infos.first.ip_address.address
    rescue
      nil
    end
  end
end
