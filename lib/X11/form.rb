require 'ostruct'

module X11
  module Form
    # A form object is an X11 packet definition. We use forms to encode
    # and decode X11 packets as we send and receive them over a socket.
    #
    # We can create a packet definition as follows:
    #
    #   class Point < BaseForm
    #     field :x, Int8
    #     field :y, Int8
    #   end
    #
    #   p = Point.new(10,20)
    #   p.x => 10
    #   p.y => 20
    #   p.to_packet => "\n\x14"
    #
    # You can also read from a socket:
    #
    #   Point.from_packet(socket) => #<Point @x=10 @y=20>
    #
    class BaseForm
      include X11::Type

      # initialize field accessors
      def initialize(*params)
        self.class.fields.each do |f|
          param = params.shift
          instance_variable_set("@#{f.name}", param)
        end
      end

      def to_packet
        # fetch class level instance variable holding defined fields
        structs = self.class.instance_variable_get("@structs")

        packet = structs.map do |s|
          # fetch value of field set in initialization
          value = instance_variable_get("@#{s.name}")

          case s.type
          when :field
            if value.is_a?(BaseForm)
              value.to_packet
            else
              s.type_klass.pack(value)
            end
          when :unused
            "\x00" * s.size
          when :length
            s.type_klass.pack(value.size)
          when :string
            s.type_klass.pack(value)
          when :list
            value.collect do |obj|
              obj.to_packet
            end
          end
        end.join
      end

      class << self
        def from_packet(socket)
          # fetch class level instance variable holding defined fields

          form = new
          lengths = {}

          @structs.each do |s|
            case s.type
            when :field
              val = if s.type_klass.superclass == BaseForm
                s.type_klass.from_packet(socket)
              else
                s.type_klass.unpack( socket.read(s.type_klass.size) )
              end
              form.instance_variable_set("@#{s.name}", val)
            when :unused
              socket.read(s.size)
            when :length
              size = s.type_klass.unpack( socket.read(s.type_klass.size) )
              lengths[s.name] = size
            when :string
              val = s.type_klass.unpack(socket, lengths[s.name])
              form.instance_variable_set("@#{s.name}", val)
            when :list
              val = lengths[s.name].times.collect do
                s.type_klass.from_packet(socket)
              end
              form.instance_variable_set("@#{s.name}", val)
            end
          end

          return form
        end

        def field(*args)
          name, type_klass, type = args
          class_eval { attr_accessor name }

          s = OpenStruct.new
          s.name = name
          s.type = (type == nil ? :field : type)
          s.type_klass = type_klass

          @structs ||= []
          @structs << s
        end

        def unused(size)
          s = OpenStruct.new
          s.size = size
          s.type = :unused

          @structs ||= []
          @structs << s
        end

        def fields
          @structs.dup.delete_if{|s| s.type == :unused or s.type == :length}
        end
      end
    end

    ##
    ## X11 Packet Defintions
    ##

    class ClientHandshake < BaseForm
      field :byte_order, Uint8
      unused 1
      field :protocol_major_version, Uint16
      field :protocol_minor_version, Uint16
      field :auth_proto_name, Uint16, :length
      field :auth_proto_data, Uint16, :length
      unused 2
      field :auth_proto_name, String8, :string
      field :auth_proto_data, String8, :string
    end

    class FormatInfo < BaseForm
      field :depth, Uint8
      field :bits_per_pixel, Uint8
      field :scanline_pad, Uint8
      unused 5
    end

    class VisualInfo < BaseForm
      field :visual_id, VisualID
      field :qlass, Uint8
      field :bits_per_rgb_value, Uint8
      field :colormap_entries, Uint16
      field :red_mask,  Uint32
      field :green_mask, Uint32
      field :blue_mask, Uint32
      unused 4
    end

    class DepthInfo < BaseForm
      field :depth, Uint8
      unused 1
      field :visuals, Uint16, :length
      unused 4
      field :visuals, VisualInfo, :list
    end

    class ScreenInfo < BaseForm
      field :root, Window
      field :default_colormap, Colormap
      field :white_pixel, Colornum
      field :black_pixel, Colornum
      field :current_input_masks, Mask
      field :width_in_pixels, Uint16
      field :height_in_pixels, Uint16
      field :width_in_millimeters, Uint16
      field :height_in_millimeters, Uint16
      field :min_installed_maps, Uint16
      field :max_installed_maps, Uint16
      field :root_visual, VisualID
      field :backing_stores, Uint8
      field :save_unders, Bool
      field :root_depth, Uint8
      field :depths, Uint8,:length
      field :depths, DepthInfo, :list
    end

    class DisplayInfo < BaseForm
      field :release_number, Uint32
      field :resource_id_base, Uint32
      field :resource_id_mask, Uint32
      field :motion_buffer_size, Uint32
      field :vendor, Uint16, :length
      field :maximum_request_length, Uint16
      field :screens, Uint8, :length
      field :formats, Uint8, :length
      field :image_byte_order, Signifigance
      field :bitmap_bit_order, Signifigance
      field :bitmap_format_scanline_unit, Uint8
      field :bitmap_format_scanline_pad, Uint8
      field :min_keycode, KeyCode
      field :max_keycode, KeyCode
      unused 4
      field :vendor, String8, :string
      field :formats, FormatInfo, :list
      field :screens, ScreenInfo, :list
    end
  end
end
