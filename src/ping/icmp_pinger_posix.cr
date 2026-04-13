module Ping
  {% unless flag?(:win32) %}
    class ICMPPinger
      ECHO_REQUEST = 8_u8
      HEADER_SIZE  =    8
      PACKET_SIZE  = HEADER_SIZE + PAYLOAD.bytesize
      IPPROTO_ICMP = Socket::Protocol.new(1)

      private def run_socket_loop(resolved : String, schedule : FixedPeriodSchedule) : Nil
        addr = Socket::IPAddress.new(resolved, 0)
        sock = Socket.new(Socket::Family::INET, Socket::Type::DGRAM, IPPROTO_ICMP)
        sock.read_timeout = TIMEOUT

        begin
          while @running
            sleep_until(schedule.remaining(Time.instant))
            break unless @running

            schedule.mark_sent
            seq = ((@sequence &+= 1) & 0xffff).to_u16
            result = send_and_receive_socket(sock, addr, seq)
            @on_sample.call(result)
            @on_log.call(result.raw_line)
          end
        ensure
          sock.close
        end
      end

      private def send_and_receive_socket(sock : Socket, addr : Socket::IPAddress, seq : UInt16) : SampleInput
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
        PAYLOAD.bytes.each_with_index { |byte, i| pkt[8 + i] = byte.to_u8 }
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
    end
  {% end %}
end
