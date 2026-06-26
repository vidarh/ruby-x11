# frozen_string_literal: true

require_relative "form"

module X11
  module Form
    # Generic request decoding, derived from the Form definitions themselves —
    # there is no separate opcode table and no per-handler decode. A request
    # class is any X11::Form class declaring an :opcode field with a constant
    # value; the opcode is that value and the name is the class name.
    #
    #   X11::Form.request_class(8)        # => X11::Form::MapWindow
    #   X11::Form.request_name(8)         # => "MapWindow"
    #   X11::Form.decode_request(8, b, c) # => #<MapWindow window=...>
    class << self
      def requests_by_opcode
        @requests_by_opcode ||= constants.each_with_object({}) do |c, h|
          # *Header forms are server-side partial decoders for variable-data
          # requests; the full form owns the opcode in the registry.
          next if c.to_s.end_with?("Header")
          k = const_get(c)
          next unless k.is_a?(Class) && k.respond_to?(:structs)
          op = k.structs.find { |s| s.name == :opcode && s.value.is_a?(Integer) }
          h[op.value] = k if op
        end
      end

      def request_class(opcode) = requests_by_opcode[opcode]
      def request_name(opcode) = requests_by_opcode[opcode]&.name&.split("::")&.last

      # Decode a request body by opcode. Returns nil for opcodes with no defined
      # form (the caller logs/consumes it as unimplemented).
      def decode_request(opcode, bytes, ctx = nil)
        request_class(opcode)&.decode(bytes, ctx)
      end
    end
  end
end
