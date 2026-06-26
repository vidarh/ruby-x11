# This module is used for encoding Ruby Objects to binary
# data. The types Int8, Int16, etc. are data-types defined
# in the X11 protocol.

module X11
  module Type

    class BaseType
      @directive = nil
      @bytesize = nil

      # `ctx` is nil/Display (client → native order) or an X11::Context (server →
      # explicit order). Multi-byte directives gain "<"/">" only for a Context, so
      # the client path stays byte-identical.
      def self.config(d,b)
        @directive, @bytesize = d, b
        @dir_lsb = b > 1 ? "#{d}<" : d
        @dir_msb = b > 1 ? "#{d}>" : d
      end

      def self.directive(ctx = nil)
        return @directive unless ctx.is_a?(X11::Context)
        ctx.msb? ? @dir_msb : @dir_lsb
      end

      def self.pack(x, ctx = nil)
        if x.is_a?(Symbol)
          if (t = X11::Form.const_get(x)) && t.is_a?(Numeric)
            x = t
          end
        end
        [x].pack(directive(ctx))
      rescue TypeError
        raise "Expected #{self.name}, got #{x.class} (value: #{x})"
      end

      def self.unpack(x, ctx = nil) = x.nil? ? nil : x.unpack1(directive(ctx))
      def self.size = @bytesize
      def self.from_packet(sock, ctx = nil) = unpack(sock.read(size), ctx)
    end
    
    class Int8   < BaseType; config("c",1); end
    class Int16  < BaseType; config("s",2); end
    class Int32  < BaseType; config("l",4); end
    class Uint8  < BaseType; config("C",1); end
    class Uint16 < BaseType; config("S",2); end
    class Uint32 < BaseType; config("L",4); end
    
    class Message
      def self.pack(x, ctx = nil) = x.b
      def self.unpack(x, ctx = nil)   = x.b
      def self.size        = 20
      def self.from_packet(sock, ctx = nil) = sock.read(2).b
    end

    class String8
      def self.pack(x, dpy) = (x.b + "\x00"*(-x.length & 3))

      def self.unpack(socket, size)
        raise "Expected size for String8" if size.nil?
        val = socket.read(size)
        unused_padding = (4 - (size % 4)) % 4
        socket.read(unused_padding)
        val
      end
    end

    class String16
      def self.pack(x, dpy)
        x.encode("UTF-16BE").b + "\x00\x00"*(-x.length & 1)
      end

      def self.unpack(socket, size)
        val = socket.read(size)
        unused_padding = (4 - (size % 4)) % 4
        socket.read(unused_padding)
        val.force_encoding("UTF-16BE")
      end
    end


    class String8Unpadded
      def self.pack(x,dpy) = x
      def self.unpack(socket, size) = socket.read(size)
    end
      
    class Bool
      # Accept true/false (client) or 0/1 (server) — note 0 is truthy in Ruby.
      def self.pack(x, ctx = nil) = (x && x != 0 ? "\x01" : "\x00")
      def self.unpack(str, ctx = nil)  = (str[0] == "\x01")
      def self.size = 1
      def self.from_packet(sock, ctx = nil) = unpack(sock.read(size), ctx)
    end
    
    KeyCode      = Uint8
    Signifigance = Uint8
    BitGravity   = Uint8
    WinGravity   = Uint8
    BackingStore = Uint8
    Bitmask      = Uint32
    Window       = Uint32
    Pixmap       = Uint32
    Cursor       = Uint32
    Colornum     = Uint32
    Font         = Uint32
    Gcontext     = Uint32
    Colormap     = Uint32
    Drawable     = Uint32
    Fontable     = Uint32
    VisualID     = Uint32
    Mask         = Uint32
    Timestamp    = Uint32
    Keysym       = Uint32

    class Atom
      # Client: ctx is a Display, value is a name/symbol to intern (exact legacy
      # behaviour). Server: ctx is an X11::Context, value is already a numeric id.
      def self.pack(x, ctx = nil)
        if ctx.is_a?(X11::Context)
          [x].pack(ctx.msb? ? "L>" : "L<")
        else
          [ctx.atom(x)].pack("L")
        end
      end
      def self.unpack(x, ctx = nil)
        return nil if x.nil?
        x.unpack1(ctx.is_a?(X11::Context) ? (ctx.msb? ? "L>" : "L<") : "L")
      end
      def self.size = 4
      def self.from_packet(sock, ctx = nil) = unpack(sock.read(size), ctx)
    end
  end
end
