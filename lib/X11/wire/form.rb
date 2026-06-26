# frozen_string_literal: true

require "stringio"
require_relative "type"

module X11
  module Wire
    # Declarative packet definition — direction-agnostic, byte-order-aware.
    # Generalizes the client's X11::Form::BaseForm with two changes that let the
    # SAME record serve a client and a server:
    #
    #   1. encode/decode take a Context (byte order) instead of a `dpy`;
    #   2. every form supports BOTH directions — `decode` (server reads requests,
    #      client reads replies/events) and `encode` (the inverse).
    #
    # DSL:
    #   field   :name, Type, value: const_or_proc   # a wire field (value: => computed/constant)
    #   unused  n                                    # n zero bytes
    #   length!                                      # u16 = total packet length / 4 (patched in on encode)
    #   string8 :name, length: :other_field          # length-prefixed 8-bit string, padded to 4
    #   value_list :name, mask: :value_mask          # X11 LISTofVALUE: one u32 per set bit in mask
    #   raw     :name, size: n                        # fixed-size raw bytes
    #
    # Usage:
    #   MapWindow.new(window: 0x4001).encode(ctx)        => bytes
    #   MapWindow.decode(bytes, ctx).window              => 0x4001
    class Form
      include Type # so subclasses can name Uint8/Uint16/... unqualified

      Slot = Struct.new(:kind, :name, :type, :opts)

      class << self
        def slots
          @slots ||= (superclass.respond_to?(:slots) ? superclass.slots.dup : [])
        end

        def field(name, type, value: nil)
          slots << Slot.new(:field, name, type, { value: value })
          define_accessor(name)
        end

        def unused(count) = slots << Slot.new(:unused, nil, nil, { size: count })

        # u16 holding total packet length in 4-byte units; filled in during encode.
        def length! = slots << Slot.new(:length, :__length__, Type::Uint16, {})

        def string8(name, length:)
          slots << Slot.new(:string8, name, nil, { length: length })
          define_accessor(name)
        end

        def value_list(name, mask:)
          slots << Slot.new(:value_list, name, Type::Uint32, { mask: mask })
          define_accessor(name)
        end

        # Fixed-size raw byte field (e.g. ClientMessage's 20-byte data).
        def raw(name, size:)
          slots << Slot.new(:raw, name, nil, { size: size })
          define_accessor(name)
        end

        def decode(data, ctx)
          io = data.respond_to?(:read) ? data : StringIO.new(String.new(data, encoding: Encoding::BINARY))
          obj = new
          slots.each do |slot|
            case slot.kind
            when :field
              obj[slot.name] = slot.type.read(io, ctx)
            when :length
              obj[:__length__] = Type::Uint16.read(io, ctx)
            when :unused
              io.read(slot.opts[:size])
            when :string8
              len = obj[slot.opts[:length]]
              raise "string8 #{slot.name}: length field #{slot.opts[:length]} not decoded yet" if len.nil?

              obj[slot.name] = io.read(len) || +""
              io.read((-len) & 3) # consume padding
            when :value_list
              count = popcount(obj.fetch(slot.opts[:mask], 0))
              obj[slot.name] = Array.new(count) { slot.type.read(io, ctx) }
            when :raw
              obj[slot.name] = io.read(slot.opts[:size]) || +""
            end
          end
          obj
        end

        def popcount(int) = int.to_s(2).count("1")

        private

        def define_accessor(name)
          define_method(name) { @values[name] }
          define_method("#{name}=") { |v| @values[name] = v }
        end
      end

      def initialize(**fields)
        @values = {}
        fields.each { |k, v| @values[k] = v }
      end

      def [](key) = @values[key]

      def []=(key, value)
        @values[key] = value
      end

      def fetch(key, default = nil) = @values.fetch(key, default)
      def to_h = @values.dup

      def encode(ctx)
        out = +"".b
        length_at = nil

        self.class.slots.each do |slot|
          case slot.kind
          when :field
            out << slot.type.pack(resolve_field(slot), ctx)
          when :length
            length_at = out.bytesize
            out << "\x00\x00".b # placeholder, patched below
          when :unused
            out << ("\x00".b * slot.opts[:size])
          when :string8
            str = String.new(@values[slot.name].to_s, encoding: Encoding::BINARY)
            out << str << ("\x00".b * ((-str.bytesize) & 3))
          when :value_list
            Array(@values[slot.name]).each { |v| out << slot.type.pack(v, ctx) }
          when :raw
            s = String.new(@values[slot.name].to_s, encoding: Encoding::BINARY)
            size = slot.opts[:size]
            out << (s.bytesize >= size ? s.byteslice(0, size) : s + ("\x00".b * (size - s.bytesize)))
          end
        end

        if length_at
          unless (out.bytesize % 4).zero?
            raise "#{self.class}: packet not 4-byte aligned (#{out.bytesize}B) — length field would be wrong"
          end

          out[length_at, 2] = [out.bytesize / 4].pack(ctx.u16)
        end

        out
      end

      private

      def resolve_field(slot)
        v = slot.opts[:value]
        return @values[slot.name] if v.nil?

        v.respond_to?(:call) ? v.call(self) : v
      end
    end
  end
end
