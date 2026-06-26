# frozen_string_literal: true

module X11
  # Per-connection codec context: the byte order in effect for a connection.
  #
  # A client always uses its own native order, so the legacy codec baked native
  # pack directives ("S","L") into the types and never needed this. A *server*
  # must honour whatever order each client chose in its setup byte, so when a
  # Context is passed to Type/Form encode/decode the directives become explicit
  # ("S<"/"S>"). Passing no Context (or a Display) keeps the native client path.
  class Context
    attr_reader :order

    def self.lsb = new(:lsb)
    def self.msb = new(:msb)
    def self.native = new([1].pack("S").getbyte(0) == 1 ? :lsb : :msb)

    # X11 setup byte-order byte: 0x42 'B' = MSB, 0x6C 'l' = LSB.
    def self.from_setup_byte(byte)
      byte = byte.ord if byte.is_a?(String)
      case byte
      when 0x42 then new(:msb)
      when 0x6C then new(:lsb)
      else raise ArgumentError, format("bad byte-order byte: 0x%02X", byte)
      end
    end

    def initialize(order) = @order = order
    def msb? = @order == :msb

    # Pack/unpack directives for callers that build/parse packets by hand
    # (e.g. a server's extension reply builders) rather than via a Form.
    def u8 = "C"
    def i8 = "c"
    def u16 = msb? ? "S>" : "S<"
    def i16 = msb? ? "s>" : "s<"
    def u32 = msb? ? "L>" : "L<"
    def i32 = msb? ? "l>" : "l<"
  end
end
