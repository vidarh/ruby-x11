# FIXME: Temp workaround
require 'stringio'

module X11

  class DisplayError < X11Error; end
  class ConnectionError < X11Error; end
  class AuthorizationError < X11Error; end
  class ProtocolError < X11Error; end

  class Display
    attr_accessor :socket

    # Open a connection to the specified display (numbered from 0) on the specified host
    def initialize(target = ENV['DISPLAY'])
      target =~ /^([\w.-]*):(\d+)(?:.(\d+))?$/
      host, display_id, screen_id = $1, $2, $3
      family = nil

      if host.empty?
        @socket = UNIXSocket.new("/tmp/.X11-unix/X#{display_id}")
        family = :Local
        host = nil
      else
        @socket = TCPSocket.new(host,6000+display_id)
        family = :Internet
      end

      authorize(host, family, display_id)
      @requestseq = 1
      @queue = []
    end

    def screens
      @internal.screens.map do |s|
        Screen.new(self, s)
      end
    end

    ##
    # The resource-id-mask contains a single contiguous set of bits (at least 18).
    # The client allocates resource IDs for types WINDOW, PIXMAP, CURSOR, FONT,
    # GCONTEXT, and COLORMAP by choosing a value with only some subset of these
    # bits set and ORing it with resource-id-base.

    def new_id
      id = (@xid_next ||= 0)
      @xid_next += 1

      (id & @internal.resource_id_mask) | @internal.resource_id_base
    end

    def read_error data
      error = Form::Error.from_packet(StringIO.new(data))
      STDERR.puts "ERROR: #{error.inspect}"
      error
    end

    def read_reply data
      len = data.unpack("@4L")[0]
      extra = len > 0 ? @socket.read(len*4) : ""
      #STDERR.puts "REPLY: #{data.inspect}"
      #STDERR.puts "EXTRA: #{extra.inspect}"
      data + extra
    end

    def read_event type, data, event_class
      case type
      when 12
        return Form::Expose.from_packet(StringIO.new(data))
      when 19
        return Form::MapNotify.from_packet(StringIO.new(data))
      when 22
        return Form::ConfigureNotify.from_packet(StringIO.new(data))
      else
        STDERR.puts "FIXME: Event: #{type}"
        STDERR.puts "EVENT: #{data.inspect}"
      end
    end

    def read_full_packet(len = 32)
      data = @socket.read_nonblock(32)
      return nil if data.nil?
      while data.length < 32
        IO.select([@socket],nil,nil,0.001)
        data.concat(@socket.read_nonblock(32 - data.length))
      end
      return data
    rescue IO::WaitReadable
      return nil
    end

    def read_packet timeout=5.0
      IO.select([@socket],nil,nil, timeout)
      data = read_full_packet(32)
      return nil if data.nil?

      type = data.unpack("C").first
      case type
      when 0
        read_error(data)
      when 1
        read_reply(data)
      when 2..34
        read_event(type, data, nil)
      else
        raise ProtocolError, "Unsupported reply type: #{type}"
      end
    end

    def write_request data
      p data
      data = data.to_packet if data.respond_to?(:to_packet)
      @socket.write(data)
    end

    def write_sync(data, reply=nil)
      write_request(data)
      pkt = next_reply
      return nil if !pkt
      reply ? reply.from_packet(StringIO.new(pkt)) : pkt
    end

    def next_packet
      @queue.shift || read_packet
    end

    def next_reply
      while pkt = next_packet
        if pkt.is_a?(String)
          return pkt
        else
          @queue.push(pkt)
        end
      end
    end

    def run
      loop do
        pkt = read_packet
        return if !pkt
        yield(pkt)
      end
    end
        
    private

    def authorize(host, family, display_id)
      auth = Auth.new
      auth_info = auth.get_by_hostname(host||"localhost", family, display_id)

      auth_name, auth_data = auth_info.address, auth_info.auth_data

      handshake = Form::ClientHandshake.new(
        Protocol::BYTE_ORDER,
        Protocol::MAJOR,
        Protocol::MINOR,
        auth_name,
        auth_data
      )

      @socket.write(handshake.to_packet)

      data = @socket.read(1)
      raise AuthorizationError, "Failed to read response from server" if !data

      case data.unpack("w").first
      when X11::Auth::FAILED
        len, major, minor, xlen = @socket.read(7).unpack("CSSS")
        reason = @socket.read(xlen * 4)
        reason = reason[0..len]
        raise AuthorizationError, "Connection to server failed -- (version #{major}.#{minor}) #{reason}"
      when X11::Auth::AUTHENTICATE
        raise AuthorizationError, "Connection requires authentication"
      when X11::Auth::SUCCESS
        @socket.read(7) # skip unused bytes
        @internal = Form::DisplayInfo.from_packet(@socket)
      else
        raise AuthorizationError, "Received unknown opcode #{type}"
      end
    end

    def to_s
      "#<X11::Display:0x#{object_id.to_s(16)} screens=#{@internal.screens.size}>"
    end
  end
end
