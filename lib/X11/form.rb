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
          if !f.value
            param = params.shift
            #p [f,param]
            instance_variable_set("@#{f.name}", param)
          end
        end
      end

      def to_packet
        # fetch class level instance variable holding defined fields
        structs = self.class.instance_variable_get("@structs")

        packet = structs.map do |s|
          # fetch value of field set in initialization

          value = s.type == :unused ? nil : instance_variable_get("@#{s.name}")
          case s.type
          when :field
            if s.value
              if s.value.respond_to?(:call)
                value = s.value.call(self)
              else
                value = s.value
              end
            end

            if value.is_a?(BaseForm)
              value.to_packet
            else
              s.type_klass.pack(value)
            end
          when :unused
            sz = s.size.respond_to?(:call) ? s.size.call(self) : s.size
            "\x00" * sz
          when :length
            s.type_klass.pack(value.size)
          when :string
            s.type_klass.pack(value)
          when :list
            value.collect do |obj|
              p obj
              if obj.is_a?(BaseForm)
                obj.to_packet
              else
                s.type_klass.pack(obj)
              end
            end
          end
        end.join
      end

      class << self
        # FIXME: Doing small reads from socket is a bad idea, and
        # the protocol provides length fields that makes it unnecessary.
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
              sz = s.size.respond_to?(:call) ? s.size.call(self) : s.size
              socket.read(sz)
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

        def field(name, type_klass, type = nil, value: nil)
          # name, type_klass, type = args
          class_eval { attr_accessor name }

          s = OpenStruct.new
          s.name = name
          s.type = (type == nil ? :field : type)
          s.type_klass = type_klass
          s.value = value

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

    class Rectangle < BaseForm
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
    end

    class Error < BaseForm
      field :error, Uint8
      field :code,  Uint8
      field :sequence_number, Uint16
      field :bad_resource_id, Uint32
      field :minor_opcode, Uint16
      field :major_opcode, Uint8
      unused 21
    end


    # Requests

    CopyFromParent = 0
    InputOutput = 1
    InputOnly = 2

    CWBackPixel = 0x0002
    CWEventMask = 0x0800

    KeyPressMask           = 0x00001
    ButtonPressMask        = 0x00004
    ExposureMask           = 0x08000
    StructureNotifyMask    = 0x20000
    SubstructureNotifyMask = 0x80000

    class CreateWindow < BaseForm
      field :opcode, Uint8, value: 1
      field :depth,  Uint8
      field :request_length, Uint16, value: ->(cw) { len = 8 + cw.value_list.length; p len; len }
      field :wid, Window
      field :parent, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      field :window_class, Uint16
      field :visual, VisualID
      field :value_mask, Bitmask
      field :value_list, Uint32, :list
    end

    class MapWindow < BaseForm
      field :opcode, Uint8, value: 8
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end

    class OpenFont < BaseForm
      field :opcode, Uint8, value: 45
      unused 1
      field :request_length, Uint16, value: ->(of) {
        3+(of.name.length+3)/4
      }
      field :fid, Font
      field :name, Uint16, :length
      unused 2
      field :name, String8, :string
    end
    
    class ListFonts < BaseForm
      field :opcode, Uint8, value: 49
      unused 1
      field :request_length, Uint16, value: ->(lf) {
        2+(lf.pattern.length+4)/4
      }
      field :max_names, Uint16
      field :length_of_pattern, Uint16,value: ->(lf) {
        lf.pattern.length
      }
      field :pattern, String8
    end

    class Str < BaseForm
      field :name, Uint8, :length, value: ->(str) { str.name.length }
      field :name, String8Unpadded, :string

      def to_s
        name
      end
    end

    class ListFontsReply < BaseForm
      field :reply, Uint8, value: 1
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :names, Uint16, :length
      unused 22
      field :names, Str, :list
    end

    FunctionMask = 0x1
    PlaneMask = 0x2
    ForegroundMask = 0x04
    BackgroundMask = 0x08
    FontMask = 0x4000

    class CreateGC < BaseForm
      field :opcode, Uint8, value: 55
      unused 1
      field :request_length, Uint16, value: ->(cw) {
        len = 4 + cw.value_list.length
      }
      field :cid, Gcontext
      field :drawable, Drawable
      field :value_mask, Bitmask
      field :value_list, Uint32, :list
    end

    class ChangeGC < BaseForm
      field :opcode, Uint8, value: 56
      unused 1
      field :request_length, Uint16, value: ->(ch) {
        3+ ch.value_list.length
      }
      field :gc, Gcontext
      field :value_mask, Bitmask
      field :value_list, Uint32, :list
    end

    class ClearArea < BaseForm
      field :opcode, Uint8, value: 61
      field :exposures, Bool
      field :request_length, Uint16, value: 4
      field :window, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
    end

    class PolyFillRectangle < BaseForm
      field :opcode, Uint8, value: 70
      unused 1
      field :request_length, Uint16, value: ->(ob) {
        len = 3 + 2*(Array(ob.rectangles).length)
      }
      field :drawable, Drawable
      field :gc, Uint32
      field :rectangles, Rectangle, :list
    end

    Bitmap = 0
    XYPixmap=1
    ZPixmap=2
    
    class PutImage < BaseForm
      field :opcode, Uint8, value: 72
      field :format, Uint8
      field :request_length, Uint16, value: ->(pi) {
        6+(pi.data.length+3)/4
      }
      field :drawable, Drawable
      field :gc, Gcontext
      field :width, Uint16
      field :height, Uint16
      field :dstx, Int16
      field :dsty, Int16
      field :left_pad, Uint8
      field :depth, Uint8
      unused 2
      field :data, String8 #, :string
    end

    class ImageText8 < BaseForm
      field :opcode, Uint8, value: 76
      field :n, Uint8, :length
      field :request_length, Uint16, value: ->(it) { 4+(it.n.length+4)/4 }
      field :drawable, Drawable
      field :gc, Gcontext
      field :x, Int16
      field :y, Int16
      field :n, String8, :string
    end

    # Events (page ~157)
    # FIXME: Events have quite a bit of redundancy, but unfortunately
    # BaseForm can't handle subclassing well.

    class Expose < BaseForm
      field :code, Uint8
      unused 1
      field :sequence_number, Uint16
      field :widow, Window
      field :x, Uint16
      field :y, Uint16
      field :width, Uint16
      field :height, Uint16
      field :count, Uint16
      unused 14
    end

    class MapNotify < BaseForm
      field :code, Uint8
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :override_redirect, Bool
      unused 19
    end
    
    class ConfigureNotify < BaseForm
      field :code, Uint8
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :above_sibling, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      field :override_redirect, Bool
      unused 5
    end
  end
end
