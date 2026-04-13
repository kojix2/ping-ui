module Ping
  {% if flag?(:win32) %}
    class ICMPPinger
      WINDOWS_REPLY_BUFFER_PADDING = 8
      INVALID_HANDLE_VALUE_ADDRESS = UInt64::MAX
      IP_SUCCESS                   =     0_u32
      IP_REQ_TIMED_OUT             = 11010_u32

      private def run_windows_loop(resolved : String, schedule : FixedPeriodSchedule) : Nil
        handle = LibIphlpapi.icmp_create_file
        raise "IcmpCreateFile failed with error #{LibKernel32.get_last_error}" if invalid_windows_handle?(handle)

        begin
          while @running
            sleep_until(schedule.remaining(Time.instant))
            break unless @running

            schedule.mark_sent
            seq = ((@sequence &+= 1) & 0xffff).to_u16
            result = send_and_receive_windows(handle, resolved, seq)
            @on_sample.call(result)
            @on_log.call(result.raw_line)
          end
        ensure
          LibIphlpapi.icmp_close_handle(handle) unless invalid_windows_handle?(handle)
        end
      end

      private def send_and_receive_windows(handle : LibIphlpapi::Handle, resolved : String, seq : UInt16) : SampleInput
        request_data = PAYLOAD.to_slice
        reply_buffer = Bytes.new(sizeof(LibIphlpapi::IcmpEchoReply32) + request_data.size + WINDOWS_REPLY_BUFFER_PADDING, 0_u8)
        response_count = LibIphlpapi.icmp_send_echo(
          handle,
          ipv4_to_ip_addr(resolved),
          request_data.to_unsafe.as(Void*),
          request_data.size.to_u16,
          Pointer(Void).null,
          reply_buffer.to_unsafe.as(Void*),
          reply_buffer.size.to_u32,
          TIMEOUT.total_milliseconds.to_u32,
        )

        if response_count == 0
          error_code = LibKernel32.get_last_error
          raw = "Error: #{windows_error_message(error_code)} (icmp_seq=#{seq})"
          return SampleInput.new(Time.local, seq.to_i32, raw, false, nil, :failure)
        end

        reply = reply_buffer.to_unsafe.as(Pointer(LibIphlpapi::IcmpEchoReply32)).value
        case reply.status
        when IP_SUCCESS
          rtt = reply.round_trip_time.to_f64
          raw = "#{reply.data_size} bytes from #{resolved}: icmp_seq=#{seq} time=#{rtt.round(2)} ms"
          SampleInput.new(Time.local, seq.to_i32, raw, true, rtt, :success)
        when IP_REQ_TIMED_OUT
          raw = "Request timeout for icmp_seq #{seq}"
          SampleInput.new(Time.local, seq.to_i32, raw, false, nil, :timeout)
        else
          raw = "Error: #{windows_ip_status_message(reply.status)} (icmp_seq=#{seq})"
          SampleInput.new(Time.local, seq.to_i32, raw, false, nil, :failure)
        end
      end

      private def invalid_windows_handle?(handle : LibIphlpapi::Handle) : Bool
        handle.null? || handle.address == INVALID_HANDLE_VALUE_ADDRESS
      end

      private def ipv4_to_ip_addr(address : String) : UInt32
        octets = address.split('.')
        raise "invalid IPv4 address: #{address}" unless octets.size == 4

        value = 0_u32
        octets.each_with_index do |octet, index|
          part = octet.to_u8
          value |= part.to_u32 << (8 * index)
        end
        value
      rescue ex
        raise "failed to encode IPv4 address #{address}: #{ex.message}"
      end

      private def windows_error_message(error_code : UInt32) : String
        case error_code
        when 0
          "IcmpSendEcho returned no replies"
        when 122_u32
          "reply buffer too small"
        when 123_u32
          "invalid parameter"
        when 50_u32
          "IPv4 stack not available"
        else
          "Win32 error #{error_code}"
        end
      end

      private def windows_ip_status_message(status : UInt32) : String
        case status
        when 11001_u32 then "reply buffer too small"
        when 11002_u32 then "destination network unreachable"
        when 11003_u32 then "destination host unreachable"
        when 11004_u32 then "destination protocol unreachable"
        when 11005_u32 then "destination port unreachable"
        when 11006_u32 then "insufficient IP resources"
        when 11007_u32 then "bad IP option"
        when 11008_u32 then "hardware error"
        when 11009_u32 then "packet too big"
        when 11010_u32 then "request timed out"
        when 11011_u32 then "bad request"
        when 11012_u32 then "bad route"
        when 11013_u32 then "TTL expired in transit"
        when 11014_u32 then "TTL expired during reassembly"
        when 11015_u32 then "parameter problem"
        when 11016_u32 then "source quench"
        when 11017_u32 then "IP option too big"
        when 11018_u32 then "bad destination"
        when 11050_u32 then "general failure"
        else
          "IP status #{status}"
        end
      end
    end
  {% end %}
end
