# frozen_string_literal: true

require_relative "endian"

module X11
  module Wire
    # Per-connection codec context. Carries the byte order in effect and hands out
    # the matching pack/unpack directives. This replaces the client codec's `dpy`
    # parameter for *wire* purposes: a client can use native order (Context.native),
    # while a server honours each connection's chosen order. (Atom interning and
    # other display policy stays in the client layer, not here.)
    class Context
      attr_reader :order

      def self.lsb = new(:lsb)
      def self.msb = new(:msb)
      def self.native = new(Endian.native)
      def self.from_setup_byte(byte) = new(Endian.from_setup_byte(byte))

      def initialize(order)
        @order = order
        @dirs = Endian::DIRECTIVES.fetch(order)
      end

      def u8 = "C"
      def i8 = "c"
      def u16 = @dirs[:u16]
      def i16 = @dirs[:i16]
      def u32 = @dirs[:u32]
      def i32 = @dirs[:i32]
    end
  end
end
