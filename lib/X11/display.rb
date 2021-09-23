module X11

  class DisplayError < X11Error; end
  class ConnectionError < X11Error; end
  class AuthorizationError < X11Error; end

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

    private

    def authorize(host, family, display_id)
      auth_info = Auth.new.get_by_hostname(host||"localhost", family, display_id)
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
