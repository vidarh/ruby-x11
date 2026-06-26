# frozen_string_literal: true

module X11
  module Wire
    # Primitive wire types. Each knows its fixed byte size and an endianness-aware
    # pack directive (resolved from the Context). This is the byte-order-aware
    # generalization of the client's native-order X11::Type — the one change that
    # makes the same definitions usable from a server.
    module Type
      class Base
        class << self
          # Declare wire size + how to derive the pack directive from a Context.
          def wire(size, &directive)
            @size = size
            define_singleton_method(:directive, &directive)
          end

          def size = @size
          def pack(value, ctx) = [Integer(value)].pack(directive(ctx))
          def unpack(bytes, ctx) = bytes.unpack1(directive(ctx))

          def read(io, ctx)
            raw = io.read(size)
            raise EOFError, "short read for #{name} (wanted #{size}B)" if raw.nil? || raw.bytesize < size

            unpack(raw, ctx)
          end
        end
      end

      class Uint8  < Base; wire(1) { |_ctx| "C" }; end
      class Int8   < Base; wire(1) { |_ctx| "c" }; end
      class Uint16 < Base; wire(2) { |ctx| ctx.u16 }; end
      class Int16  < Base; wire(2) { |ctx| ctx.i16 }; end
      class Uint32 < Base; wire(4) { |ctx| ctx.u32 }; end
      class Int32  < Base; wire(4) { |ctx| ctx.i32 }; end

      # Aliases matching X11 spec vocabulary.
      Card8  = Uint8
      Card16 = Uint16
      Card32 = Uint32
      Bool   = Uint8
    end
  end
end
