require "socket"

module Ping
  # Native Crystal ICMP ping using SOCK_DGRAM + IPPROTO_ICMP.
  # On macOS regular users can open ICMP datagram sockets without root.
  # Each ping session runs in a dedicated OS thread (Fiber::ExecutionContext::Isolated)
  # so it doesn't block the UIng event loop on the main thread.
  class ICMPPinger
    ECHO_REQUEST     = 8_u8
    ECHO_REPLY       = 0_u8
    HEADER_SIZE      =    8
    PAYLOAD          = "CrystalPingMon  " # exactly 16 bytes
    PACKET_SIZE      = HEADER_SIZE + PAYLOAD.bytesize
    DEFAULT_INTERVAL = 1.second
    TIMEOUT          = 2.seconds

    # IPPROTO_ICMP = 1, expressed as a Protocol enum value
    IPPROTO_ICMP = Socket::Protocol.new(1)

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
        @running = false
        @on_finished.call("Cannot resolve: #{host}")
        return
      end

      addr = Socket::IPAddress.new(resolved, 0)
      @on_log.call("PING #{host} (#{resolved}): #{PAYLOAD.bytesize} data bytes")

      sock = Socket.new(Socket::Family::INET, Socket::Type::DGRAM, IPPROTO_ICMP)
      sock.read_timeout = TIMEOUT

      begin
        while @running
          seq = ((@sequence &+= 1) & 0xffff).to_u16
          result = send_and_receive(sock, addr, seq)
          @on_sample.call(result)
          @on_log.call(result.raw_line)
          sleep @interval if @running
        end
      ensure
        sock.close
      end

      @running = false
      @on_finished.call(nil)
    rescue ex
      @running = false
      @on_finished.call(ex.message)
    end

    private def send_and_receive(sock : Socket, addr : Socket::IPAddress, seq : UInt16) : SampleInput
      pkt = build_request(seq)
      t0 = Time.instant
      sock.send(pkt, to: addr)

      buf = Bytes.new(64)
      sock.receive(buf)
      rtt = (Time.instant - t0).total_milliseconds

      raw = "#{PAYLOAD.bytesize} bytes from #{addr.address}: icmp_seq=#{seq} time=#{rtt.round(2)} ms"
      SampleInput.new(Time.local, seq.to_i32, raw, true, rtt, :success)
    rescue IO::TimeoutError
      raw = "Request timeout for icmp_seq #{seq}"
      SampleInput.new(Time.local, seq.to_i32, raw, false, nil, :timeout)
    rescue ex : Socket::Error | IO::Error
      raw = "Error: #{ex.message} (icmp_seq=#{seq})"
      SampleInput.new(Time.local, seq.to_i32, raw, false, nil, :failure)
    end

    private def build_request(seq : UInt16) : Bytes
      pkt = Bytes.new(PACKET_SIZE, 0_u8)
      pkt[0] = ECHO_REQUEST
      # [1] code = 0
      # [2..3] checksum filled below
      # [4..5] identifier = 0  (macOS kernel replaces with socket's ephemeral id for DGRAM ICMP)
      pkt[6] = (seq >> 8).to_u8
      pkt[7] = (seq & 0xff).to_u8
      PAYLOAD.bytes.each_with_index { |b, i| pkt[8 + i] = b.to_u8 }
      csum = icmp_checksum(pkt)
      pkt[2] = (csum >> 8).to_u8
      pkt[3] = (csum & 0xff).to_u8
      pkt
    end

    private def icmp_checksum(data : Bytes) : UInt16
      sum = 0_u32
      i = 0
      while i + 1 < data.size
        sum &+= (data[i].to_u32 << 8) | data[i + 1].to_u32
        i += 2
      end
      sum &+= data[data.size - 1].to_u32 << 8 if data.size.odd?
      while (sum >> 16) != 0
        sum = (sum & 0xffff) &+ (sum >> 16)
      end

      checksum = (~sum) & 0xffff_u32
      checksum.to_u16
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
