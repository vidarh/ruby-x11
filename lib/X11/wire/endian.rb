# frozen_string_literal: true

module X11
  # X11::Wire — the shared, direction-agnostic wire codec used by BOTH the
  # pure-x11 client and the X12 server. See docs (codec fold-back): the codec
  # lives here; X12 depends on it instead of carrying its own copy.
  module Wire
    # Per-connection byte order.
    #
    # An X11 client picks the byte order in the first byte of its setup request
    # (0x42 'B' = MSB/big-endian, 0x6C 'l' = LSB/little-endian) and it holds for
    # the whole connection. A *server* therefore cannot use native-endian pack
    # directives the way a single-endianness client can — it must honour whatever
    # the client chose. So directives are parameterized by order here. (A client
    # simply uses its own native order; see Context.native.)
    module Endian
      DIRECTIVES = {
        lsb: { u16: "S<", u32: "L<", i16: "s<", i32: "l<" }.freeze,
        msb: { u16: "S>", u32: "L>", i16: "s>", i32: "l>" }.freeze,
      }.freeze

      module_function

      # Map the X11 setup byte-order byte to :lsb / :msb.
      def from_setup_byte(byte)
        byte = byte.ord if byte.is_a?(String)
        case byte
        when 0x42 then :msb # 'B'
        when 0x6C then :lsb # 'l'
        else raise ArgumentError, format("bad byte-order byte: 0x%02X", byte)
        end
      end

      # The byte order of the running Ruby process (what a client uses).
      def native = [1].pack("S").getbyte(0) == 1 ? :lsb : :msb

      def u16(order) = DIRECTIVES.fetch(order).fetch(:u16)
      def u32(order) = DIRECTIVES.fetch(order).fetch(:u32)
      def i16(order) = DIRECTIVES.fetch(order).fetch(:i16)
      def i32(order) = DIRECTIVES.fetch(order).fetch(:i32)
    end
  end
end
