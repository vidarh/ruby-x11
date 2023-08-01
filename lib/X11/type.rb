# This module is used for encoding Ruby Objects to binary
# data. The types Int8, Int16, etc. are data-types defined
# in the X11 protocol. We wrap each data-type in a lambda expression
# which gets evaluated when a packet is created.

module X11
  module Type

    def self.define(type, directive, bytesize)
      eval %{
        class X11::Type::#{type}
          def self.pack(x)
            [x].pack(\"#{directive}\")
          end

          def self.unpack(x)
            x.unpack(\"#{directive}\").first
          end

          def self.size
            #{bytesize}
          end
        end
      }
    end

    # Primitive Types
    define "Int8", "c", 1
    define "Int16", "s", 2
    define "Int32", "l", 4
    define "Uint8", "C", 1
    define "Uint16", "S", 2
    define "Uint32", "L", 4

    class String8
      def self.pack(x)
        x + "\x00"*(-x.length & 3)
      end


      def self.unpack(socket, size)
        val = socket.read(size)
        unused_padding = (4 - (size % 4)) % 4
        socket.read(unused_padding)
        val
      end
    end

    class String8Unpadded
      def self.pack(x)
        x
      end


      def self.unpack(socket, size)
        val = socket.read(size)
      end
    end
    
    class Bool
      def self.pack(x)
        x ? "\x01" : "\x00"
      end

      def self.unpack(str)
        str[0] == "0x01"
      end

      def self.size
        1
      end
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

  end
end
