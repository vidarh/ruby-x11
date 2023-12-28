# This module is used for encoding Ruby Objects to binary
# data. The types Int8, Int16, etc. are data-types defined
# in the X11 protocol.

module X11
  module Type

    class BaseType
      @directive = nil
      @bytesize = nil

      def self.config(d,b) = (@directive, @bytesize = d,b)
        
      def self.pack(x)
        if x.is_a?(Symbol)
          if (t = X11::Form.const_get(x)) && t.is_a?(Numeric)
            x = t
          end
        end
        [x].pack(@directive)
      rescue TypeError => e
        raise "Expected #{self.name}, got #{x.class} (value: #{x})"
      end

      def self.unpack(x) = x.nil? ? nil  : x.unpack1(@directive)
      def self.size = @bytesize
      def self.from_packet(sock) = unpack(sock.read(size))
    end
    
    # Primitive Types
    class Int8   < BaseType; config("c",1); end
    class Int16  < BaseType; config("s",2); end
    class Int32  < BaseType; config("l",4); end
    class Uint8  < BaseType; config("C",1); end
    class Uint16 < BaseType; config("S",2); end
    class Uint32 < BaseType; config("L",4); end
    
    class Message
      def self.pack(x)   = x.b
      def self.unpack(x) = x.b
      def self.size      = 20
      def self.from_packet(sock) = sock.read(2).b
    end

    class String8
      def self.pack(x)
        x.b + "\x00"*(-x.length & 3)
      end

      def self.unpack(socket, size)
        raise "Expected size for String8" if size.nil?
        val = socket.read(size)
        unused_padding = (4 - (size % 4)) % 4
        socket.read(unused_padding)
        val
      end
    end

    class String16
      def self.pack(x)
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
      def self.pack(x) = x
      def self.unpack(socket, size) = socket.read(size)
    end
      
    class Bool
      def self.pack(x)     = (x ? "\x01" : "\x00")
      def self.unpack(str) = (str[0] == "\x01")
      def self.size = 1
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
    Atom         = Uint32
    VisualID     = Uint32
    Mask         = Uint32
    Timestamp    = Uint32
    Keysym       = Uint32
  end
end
