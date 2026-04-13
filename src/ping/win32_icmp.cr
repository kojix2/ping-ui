module Ping
  {% if flag?(:win32) %}
    @[Link("iphlpapi")]
    lib LibIphlpapi
      alias Handle = Void*
      alias IpAddr = UInt32

      struct IpOptionInformation32
        ttl : UInt8
        tos : UInt8
        flags : UInt8
        options_size : UInt8
        options_data : UInt32
      end

      struct IcmpEchoReply32
        address : IpAddr
        status : UInt32
        round_trip_time : UInt32
        data_size : UInt16
        reserved : UInt16
        data : UInt32
        options : IpOptionInformation32
      end

      fun icmp_create_file = IcmpCreateFile : Handle
      fun icmp_close_handle = IcmpCloseHandle(handle : Handle) : Bool
      fun icmp_send_echo = IcmpSendEcho(
        handle : Handle,
        destination_address : IpAddr,
        request_data : Void*,
        request_size : UInt16,
        request_options : Void*,
        reply_buffer : Void*,
        reply_size : UInt32,
        timeout : UInt32,
      ) : UInt32
    end

    @[Link("kernel32")]
    lib LibKernel32
      fun get_last_error = GetLastError : UInt32
    end
  {% end %}
end
