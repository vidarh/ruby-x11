
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
    class Form
      def self.structs
        []
      end

      def self.fields
        []
      end
    end

    class BaseForm < Form
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

      def to_packet(dpy)
        # fetch class level instance variable holding defined fields
        structs = self.class.structs

        structs.map do |s|
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
            #p [s,value]

            if value.is_a?(BaseForm)
              v = value.to_packet(dpy)
            else
              #p [s,value]
              v = s.type_klass.pack(value, dpy)
            end
            #p v
            v
          when :unused
            sz = s.size.respond_to?(:call) ? s.size.call(self) : s.size
            "\x00" * sz
          when :length, :format_length
            #p [s,value]
            #p [value.size]
            s.type_klass.pack(value.size, dpy)
          when :string
            s.type_klass.pack(value, dpy)
          when :list
            Array(value).collect do |obj|
              if obj.is_a?(BaseForm)
                obj.to_packet(dpy)
              else
                s.type_klass.pack(obj, dpy)
              end
            end
          end
        end.join
      end

      class << self
        def structs
          superclass.structs + Array(@structs) #instance_variable_get("@structs"))
        end

        # FIXME: Doing small reads from socket is a bad idea, and
        # the protocol provides length fields that makes it unnecessary.
        def from_packet(socket)
          # fetch class level instance variable holding defined fields

          form = new
          lengths = {}

          structs.each do |s|
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
            when :format_length
              size = s.type_klass.unpack( socket.read(s.type_klass.size) )
              lengths[s.name] = case form.format
                                when 8 then size
                                when 16 then size*2
                                when 32 then size*4
                                else 0
                                end
            when :string
              len = lengths[s.name]
              val = s.type_klass.unpack(socket, len)
              form.instance_variable_set("@#{s.name}", val)
            when :list
              len = lengths[s.name]
              if len
                val = len.times.collect do
                  s.type_klass.from_packet(socket)
                end
              else
                val = []
                while ob = s.type_klass.from_packet(socket)
                  val << ob
                end
              end
              form.instance_variable_set("@#{s.name}", val)
            end
          end

          return form
        end

        Field = Struct.new(:name, :type, :type_klass, :value, :size, keyword_init: true)
        
        def field(name, type_klass, type = nil, value: nil)
          # name, type_klass, type = args
          class_eval do
            if value && value.respond_to?(:call)
              define_method(name.to_sym) { value.call(self) }
            elsif type != :length && type != :format_length
              attr_accessor name
            end
          end

          s = Field.new
          s.name = name
          s.type = (type == nil ? :field : type)
          s.type_klass = type_klass
          s.value = value

          @structs ||= []
          @structs << s
        end

        def unused(size)
          @structs ||= []
          @structs << Field.new(size: size, type: :unused)
        end

        def fields
          super+Array(@structs).dup.delete_if{|s| s.type == :unused or s.type == :length or s.type == :format_length}
        end
      end
    end

    # # Predefined constants, that can be used in the form of symbols
    
    module Atoms
      PRIMARY   = 1
      SECONDARY = 2
      ARC = 3
      ATOM = 4
      BITMAP = 5
      CARDINAL = 6
      COLORMAP = 7
      CURSOR = 8
      #...
      STRING = 31
      VISUALID = 32
      WINDOW = 33
      WM_COMMAND = 34
      WM_HINTS = 35
    end

    PointerWindow = 0
    InputFocus = 1
    
    # FIXME: Deprecated in favour of the Constants module
    AtomAtom=4
    CardinalAtom=6
    WindowAtom=33
    
    ##
    ## X11 Packet Defintions
    ##

    class Reply < BaseForm
      field :reply, Uint8
    end

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
      field :release_number,     Uint32
      field :resource_id_base,   Uint32
      field :resource_id_mask,   Uint32
      field :motion_buffer_size, Uint32
      field :vendor, Uint16, :length
      field :maximum_request_length, Uint16
      field :screens, Uint8, :length
      field :formats, Uint8, :length
      field :image_byte_order, Signifigance
      field :bitmap_bit_order, Signifigance
      field :bitmap_format_scanline_unit, Uint8
      field :bitmap_format_scanline_pad,  Uint8
      field :min_keycode, KeyCode
      field :max_keycode, KeyCode
      unused 4
      field :vendor,  String8,    :string
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

      # The original request
      attr_accessor :request
    end

    # XRender structures

    class DirectFormat < BaseForm
      field :red,        Uint16
      field :red_mask,   Uint16
      field :green,      Uint16
      field :green_mask, Uint16
      field :blue,       Uint16
      field :blue_mask,  Uint16
      field :alpha,      Uint16
      field :alpha_mask, Uint16
    end

    class PictVisual < BaseForm
      field :visual, Uint32
      field :format, Uint32
    end

    class PictDepth < BaseForm
      field :depth, Uint8
      unused 1
      field :visuals, Uint16, :length
      unused 4
      field :visuals, PictVisual, :list
    end
    
    class PictScreen < BaseForm
      field :depths, Uint32, :length
      field :fallback, Uint32
      field :depths, PictDepth, :list
    end

    class PictFormInfo < BaseForm
      field :id, Uint32
      field :type, Uint8
      field :depth, Uint8
      unused 2
      field :direct, DirectFormat
      field :colormap, Colormap
    end
    
    # # Requests

    # Constants, p112 onwards
    CopyFromParent = 0
    InputOutput    = 1
    InputOnly      = 2

    CWBackPixmap  = 0x0001
    CWBackPixel   = 0x0002
    CWBorderPixmap= 0x0004
    CWBorderPixel = 0x0008
    CWBitGravity  = 0x0010
    CWWinGravity  = 0x0020
    CWBackingStore     = 0x0040
    CWBackingPlanes    = 0x0080
    CWBackingPixel     = 0x0100
    CWOverrideRedirect = 0x0200
    CWSaveUnder        = 0x0400
    CWEventMask        = 0x0800
    CWColorMap         = 0x2000

    KeyPressMask           = 0x000001
    KeyReleaseMask         = 0x000002
    ButtonPressMask        = 0x000004
    ButtonReleaseMask      = 0x000008
    EnterWindowMask        = 0x000010
    LeaveWindowMask        = 0x000020
    PointerMotionMask      = 0x000040
    PointerMotionHintMask  = 0x000080
    Button1MotionMask      = 0x000100
    # 0x200 .. 0x40000; page 113
    ExposureMask           = 0x008000
    VisibilityChangeMask   = 0x010000
    StructureNotifyMask    = 0x020000
    ResizeRedirectMask     = 0x040000
    SubstructureNotifyMask = 0x080000
    SubstructureRedirectMask=0x100000
    FocusChangeMask        = 0x200000
    PropertyChangeMask     = 0x400000
    ColormapChangeMask     = 0x800000
    OwnerGrabButtonMask    = 0x100000

    class CreateWindow < BaseForm
      field :opcode, Uint8, value: 1
      field :depth,  Uint8
      field :request_length, Uint16, value: ->(cw) { 8 + cw.value_list.length }
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

    class ChangeWindowAttributes < BaseForm
      field :opcode, Uint8, value: 2
      unused 1
      field :request_length, Uint16, value: ->(cw) { 3 + cw.value_list.length }
      field :window, Window
      field :value_mask, Bitmask
      field :value_list, Uint32, :list
    end

    class GetWindowAttributes < BaseForm
      field :opcode, Uint8, value: 3
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end

    class WindowAttributes < BaseForm
      field :reply, Uint8, value: 1
      field :backing_store, Uint8
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :visual, VisualID
      field :wclass, Uint16
      field :bit_gravity, Uint8
      field :win_gravity, Uint8
      field :backing_planes, Uint32
      field :backing_pixel, Uint32
      field :save_under, Bool
      field :map_is_installed, Bool
      field :map_state, Uint8
      field :override_redirect, Bool
      field :colormap, Colormap
      field :all_event_masks, Uint32
      field :your_event_masks, Uint32
      field :do_not_propagate_mask, Uint16
      unused 2
    end

    class DestroyWindow < BaseForm
      field :opcode, Uint8, value: 4
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end
    
    class QueryPointer < BaseForm
      field :opcode, Uint8, value: 38
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end
    
    class QueryPointerReply < Reply
      field :same_screen, Bool
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :root, Window
      field :child, Window
      field :root_x, Int16
      field :root_y, Int16
      field :win_x, Int16
      field :win_y, Int16
      field :mask, Uint16
      unused 6
    end

    class ChangeSaveSet < BaseForm
      field :opcode, Uint8, value: 6
      field :mode, Uint8
      field :request_length, Uint16, value: 2
      field :window, Window
    end
    
    class ReparentWindow < BaseForm
      field :opcode, Uint8, value: 7
      unused 1
      field :request_length, Uint16, value: 4
      field :window, Window
      field :parent, Window
      field :x, Int16
      field :y, Int16
    end
      
    class MapWindow < BaseForm
      field :opcode, Uint8, value: 8
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end

    class UnmapWindow < BaseForm
      field :opcode, Uint8, value: 10
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end

    class ConfigureWindow < BaseForm
      field :opcode, Uint8, value: 12
      unused 1
      field :request_length, Uint16, value: ->(cw) { 3 + cw.values.length }
      field :window, Window
      field :value_mask, Uint16
      unused 2
      field :values, Uint32, :list
    end

    class GetGeometry < BaseForm
      field :opcode, Uint8, value: 14
      unused 1
      field :request_length, Uint16, value: 2
      field :drawable, Drawable
    end

    class Geometry < BaseForm
      field :reply, Uint8, value: 1
      field :depth, Uint8
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :root, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      unused 10
    end

    class QueryTree < BaseForm
      field :opcode, Uint8, value: 15
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end

    class QueryTreeReply < BaseForm
      field :reply, Uint8, value: 1
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :root, Window
      field :parent, Window
      field :children, Uint16, :length
      unused 14
      field :children, Window, :list
    end

    class InternAtom < BaseForm
      field :opcode, Uint8, value: 16
      field :only_if_exists, Bool
      field :request_length, Uint16, value: ->(ia) {
        2+(ia.name.length+3)/4
      }
      field :name, Uint16, value: ->(ia) {
        ia.name.length
      }
      unused 2
      field :name, String8, :string
    end

    class InternAtomReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :atom, Atom
      unused 20
    end

    class GetAtomName < BaseForm
      field :opcode, Uint8, value: 17
      unused 1
      field :request_length, Uint16, value: 2
      field :atom, Atom
    end

    class AtomName < Reply
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :name, Uint16, :length
      unused 22
      field :name, String8, :string
    end

    Replace = 0
    Prepend = 1
    Append = 2
    
    class ChangeProperty < BaseForm
      field :opcode, Uint8, value: 18
      field :mode, Uint8
      field :request_length, Uint16, value: ->(cp) {
        #p [:data, cp.data, :len, cp.data.length, :total, 6+(cp.data.length+3)/4]
        6+(cp.data.length+3)/4
      }
      field :window, Window
      field :property, Atom
      field :type, Atom
      field :format, Uint8
      unused 3
      field :data, Uint32, value: ->(cp) { cp.data.length / (cp.format/8) }
      field :data, Uint8, :list
    end

    class GetProperty < BaseForm
      field :opcode, Uint8, value: 20
      field :delete, Bool
      field :request_length, Uint16, value: 6
      field :window, Window
      field :property, Atom
      field :type, Atom
      field :long_offset, Uint32
      field :long_length, Uint32
    end
    
    class Property < BaseForm
      field :reply, Uint8, value: 1
      field :format, Uint8
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :type, Atom
      field :bytes_after, Uint32
      field :value, Uint32, :format_length
      unused 12
      field :value, String8, :string
    end

    class SendEvent < BaseForm
      field :opcode, Uint8, value: 25
      field :propagate, Bool
      field :request_length, Uint16, value: 11
      field :destination, Window
      field :event_mask, Uint32
      field :event, Uint32 # FIXME: This is wrong, and will break on parsing.
    end
    
    class GrabButton < BaseForm
      field :opcode, Uint8, value: 28
      field :owner_events, Bool
      field :request_length, Uint16, value: 6
      field :grab_window, Window
      field :event_mask, Uint16
      field :pointer_mode, Uint8
      field :keyboard_mode, Uint8
      field :confine_to, Window
      field :cursor, Cursor
      field :button, Uint8
      unused 1
      field :modifiers, Uint16
    end

    class GrabKey < BaseForm
      field :opcode, Uint8, value: 33
      field :owner_event, Bool
      field :request_length, Uint16, value: 4
      field :grab_window, Window
      field :modifiers, Uint16
      field :keycode, Uint8
      field :pointer_mode, Uint8
      field :keyboard_mode, Uint8
      unused 3
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

    class CreatePixmap < BaseForm
      field :opcode, Uint8, value: 53
      field :depth, Uint8
      field :request_length, Uint16, value: 4
      field :pid, Pixmap
      field :drawable, Uint32
      field :width, Uint16
      field :height, Uint16
    end
    
    class FreePixmap < BaseForm
      field :opcode, Uint8, value: 54
      unused 1
      field :request_length, Uint16, value: 2
      field :pixmap, Pixmap
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
    GraphicsExposures = 0x10000

    class CreateGC < BaseForm
      field :opcode, Uint8, value: 55
      unused 1
      field :request_length, Uint16, value: ->(cw) {
        4 + cw.value_list.length
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

    class CopyArea < BaseForm
      field :opcode, Uint8, value: 62
      unused 1
      field :request_length, Uint16, value: 7
      field :src_drawable, Drawable
      field :dst_drawable, Drawable
      field :gc, Gcontext
      field :src_x,  Uint16
      field :src_y,  Uint16
      field :dst_x,  Uint16
      field :dst_y,  Uint16
      field :width,  Uint16
      field :height, Uint16
    end

    class PolyFillRectangle < BaseForm
      field :opcode, Uint8, value: 70
      unused 1
      field :request_length, Uint16, value: ->(ob) {
        3 + 2*(Array(ob.rectangles).length)
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
      field :request_length, Uint16, value: ->(it) { 4+(it.n.length+3)/4 }
      field :drawable, Drawable
      field :gc, Gcontext
      field :x, Int16
      field :y, Int16
      field :n, String8, :string
    end

    class ImageText16 < BaseForm
      field :opcode, Uint8, value: 77
      field :n, Uint8, :length
      field :request_length, Uint16, value: ->(it) { 4+(it.n.length*2+3)/4 }
      field :drawable, Drawable
      field :gc, Gcontext
      field :x, Int16
      field :y, Int16
      field :n, String16, :string
    end

    class CreateColormap < BaseForm
      field :opcode, Uint8, value: 78
      field :alloc, Uint8
      field :request_length, Uint16, value: 4
      field :mid, Colormap
      field :window, Window
      field :visual, Uint32
    end

    class QueryExtension < BaseForm
      field :opcode, Uint8, value: 98
      unused 1
      field :request_length, Uint16, value: ->(qe) { 2+(qe.name.length+3)/4 }
      field :name, Uint16, :length
      unused 2
      field :name, String8
    end

    class QueryExtensionReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :present, Bool
      field :major_opcode, Uint8
      field :first_event, Uint8
      field :first_error, Uint8
      unused 20
    end

    class GetKeyboardMapping < BaseForm
      field :opcode, Uint8, value: 101
      unused 1
      field :request_length, Uint16, value: 2
      field :first_keycode, Uint8
      field :count, Uint8
      unused 2
    end

    class GetKeyboardMappingReply < Reply
      field :keysyms_per_keycode, Uint8
      field :sequence_number, Uint16
      field :reply_length, Uint32
      unused 24
      field :keysyms, Keysym, :list
    end

    # Events (page ~157)
    # FIXME: Events have quite a bit of redundancy, but unfortunately
    # BaseForm can't handle subclassing well.

    Shift   = 0x0001
    Lock    = 0x0002
    Control = 0x0004
    Mod1    = 0x0008
    Mod2    = 0x0010
    Mod3    = 0x0020
    Mod4    = 0x0040
    Mod5    = 0x0080
    Button1 = 0x0100
    Button2 = 0x0200
    Button3 = 0x0400
    Button4 = 0x0800
    Button5 = 0x1000

    class Event < BaseForm
      field :code, Uint8
    end

    class SimpleEvent < Event
      field :detail, Uint8
      field :sequence_number, Uint16
    end

    class InputEvent < SimpleEvent
      field :time, Uint32
      field :root, Window
      field :event, Window
      field :child, Window
      field :root_x, Int16
      field :root_y, Int16
      field :event_x, Int16
      field :event_y, Int16
      field :state, Uint16
    end

    class EnterLeaveNotify < InputEvent
      field :mode, Uint8
      field :same_screen_or_focus, Uint8

      def same_screen = same_screen_or_focus.anybit?(0x02)
      def focus = same_screen_or_focus.anybit?(0x01)
    end

    class EnterNotify < EnterLeaveNotify
    end

    class LeaveNotify < EnterLeaveNotify
    end

    class FocusIn < SimpleEvent
      field :event, Window
      field :mode, Uint8
      unused 23
    end

    class FocusOut < FocusIn
    end
      
    class PressEvent < InputEvent
      field :same_screen, Bool
      unused 1
    end

    class ButtonPress < PressEvent
    end

    class KeyPress < PressEvent
    end

    class KeyRelease < PressEvent
    end

    class MotionNotify < PressEvent
    end

    class ButtonRelease < PressEvent
    end

    class ReparentNotify < SimpleEvent
      field :event, Window
      field :window, Window
      field :parent, Window
      field :x, Int16
      field :y, Int16
      field :override_redirect, Bool
      unused 11
    end

    class ConfigureRequest < Event # 23
      field :stack_mode,      Uint8
      field :sequence_number, Uint16
      field :parent, Window
      field :window, Window
      field :sibling, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      field :value_mask, Uint16
      unused 4
    end
    
    class Expose < SimpleEvent
      field :window, Window
      field :x, Uint16
      field :y, Uint16
      field :width, Uint16
      field :height, Uint16
      field :count, Uint16
      unused 14
    end

    class NoExposure < SimpleEvent # 14
      field :drawable, Drawable
      field :minor_opcode, Uint16
      field :major_opcode, Uint8
      unused 21
    end

    class CreateNotify < SimpleEvent # 16
      field :parent, Window
      field :window, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      field :override_redirect, Bool
    end
    
    class DestroyNotify < Event
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :window, Window
      unused 20
    end
    
    class UnmapNotify < Event
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :window, Window
      field :from_configure, Bool
      unused 19
    end
    
    class MapNotify < Event
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :window, Window
      field :override_redirect, Bool
      unused 19
    end

    class MapRequest < Event
      unused 1
      field :sequence_number, Uint16
      field :parent, Window
      field :window, Window
      unused 20
    end

    class ConfigureNotify < Event
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :window, Window
      field :above_sibling, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      field :override_redirect, Bool
      unused 5
    end

    class ClientMessage < Event
      field :format, Uint8
      field :sequence_number, Uint16
      field :window, Window
      field :type, Atom
      field :data, X11::Type::Message
    end

    class PropertyNotify < Event # 28
      unused 1
      field :sequence_number, Uint16
      field :window, Window
      field :atom, Atom
      field :time, Uint32
      field :state, Uint8
      unused 15
    end


    # XRender extension
    # From https://cgit.freedesktop.org/xorg/proto/renderproto/tree/renderproto.h
    class XRenderQueryVersion < BaseForm
      field :req_type, Uint8
      field :render_req_type, Uint8, value: 0
      field :request_length, Uint16, value: 3
      field :major_version, Uint32
      field :minor_version, Uint32
    end

    class XRenderQueryVersionReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :request_length, Uint32
      field :major_version, Uint32
      field :minor_version, Uint32
      #unused 16
    end

    class XRenderQueryPictFormats < BaseForm
      field :req_type, Uint8
      field :render_req_type, Uint8, value: 1
      field :request_length, Uint16, value: 1
    end

    class XRenderQueryPictFormatsReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :length, Uint32
      field :formats, Uint32, :length
      field :screens, Uint32, :length
      field :depths, Uint32, :length
      field :visuals, Uint32, :length
      field :subpixel, Uint32, :length
      unused 4
      field :formats, PictFormInfo, :list
      field :screens, PictScreen, :list
      field :subpixels, Uint32, :list
    end

     class XRenderCreatePicture < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 4
       field :request_length, Uint16, value: ->(cp) {
         5 + Array(cp.value_list).length
       }
       field :pid, Uint32
       field :drawable, Uint32
       field :format, Uint32
       field :value_mask, Uint32
       field :value_list, Uint32, :list
     end

     class XRenderCreateGlyphSet < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 17
       field :request_length, Uint16, value: 3
       field :gsid, Uint32
       field :format, Uint32
     end

     class GlyphInfo < BaseForm
       field :width,  Uint16
       field :height, Uint16
       field :x, Int16
       field :y, Int16
       field :x_off, Int16
       field :y_off, Int16
     end

     class XRenderAddGlyphs < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 20
       field :request_length, Uint16, value: ->(ag) {
         if ag.glyphs.length != ag.glyphids.length
           raise "Mismatch: Expected XRenderAddGlyphs glyphs and glyphids to be same length"
         end

         # GlyphInfo length == 3 + Glyphid length == 1
         3 + ag.glyphs.length * 4 + (ag.data.length+3)/4
       }
       field :glyphset, Uint32
       field :glyphs,   Uint32, :length
       field :glyphids, Uint32, :list
       field :glyphs,   GlyphInfo, :list
       field :data,     String8
     end

     class XRenderColor < BaseForm
       field :red,   Uint16
       field :green, Uint16
       field :blue,  Uint16
       field :alpha, Uint16
     end

     class GlyphElt32 < BaseForm
       field :glyphs, Uint8, :length
       unused 3
       field :delta_x, Uint16
       field :delta_y, Uint16
       field :glyphs, Uint32, :list
     end

     # This is *also* the same as XRenderCOmpositeGlyphs16 and 8 w/other render_req_type,
     # but do we care?
     class XRenderCompositeGlyphs32 < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 25
       field :request_length, Uint16, value: ->(ch) {
         7 + (ch.glyphcmds[0].glyphs.length + 2) # per glyphcmd
       }
       field :op, Uint8
       unused 3
       field :src, Uint32
       field :dst, Uint32
       field :mask_format, Uint32
       field :glyphset, Uint32
       field :xsrc, Uint16
       field :ysrc, Uint16
       # FIXME:
       # We say this is a list, because technically it is
       # But currently it'll break with more than one item.
       field :glyphcmds, GlyphElt32, :list
     end

     class XRenderFillRectangles < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 26
       field :request_length, Uint16, value: ->(fr) { 5 + fr.rects.length * 2 }
       field :op, Uint8
       unused 3
       field :dst, Uint32
       field :color, Uint32
       field :rects, Rectangle, :list
     end

     class XRenderCreateSolidFill < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 33
       field :request_length, Uint16, value: 4
       field :fill, Uint32
       field :color, XRenderColor
     end

     class XRenderFreePicture < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 7
       field :request_length, Uint16, value: 2
       field :picture, Uint32
     end
     
     # Xinerama extension
     # From https://gitlab.freedesktop.org/xorg/proto/xineramaproto/-/blob/master/panoramiXproto.h
     class XineramaQueryVersion < BaseForm
       field :req_type, Uint8
       field :xinerama_req_type, Uint8, value: 0
       field :request_length, Uint16, value: 2
       field :major_version, Uint16, value: 1
       field :minor_version, Uint16, value: 0
     end

     class XineramaQueryVersionReply < Reply
       unused 1
       field :sequence_number, Uint16
       field :reply_length, Uint32
       field :major_version, Uint16
       field :minor_version, Uint16
       unused 20
     end

     class XineramaIsActive < BaseForm
       field :req_type, Uint8
       field :xinerama_req_type, Uint8, value: 4
       field :request_length, Uint16, value: 1
     end

     class XineramaIsActiveReply < Reply
       unused 1
       field :sequence_number, Uint16
       field :reply_length, Uint32
       field :state, Uint32
       unused 20
     end

     class XineramaScreenInfo < BaseForm
       field :x_org, Int16
       field :y_org, Int16
       field :width, Uint16
       field :height, Uint16
     end

     class XineramaQueryScreens < BaseForm
       field :req_type, Uint8
       field :xinerama_req_type, Uint8, value: 5
       field :request_length, Uint16, value: 1
     end

     class XineramaQueryScreensReply < Reply
       unused 1
       field :sequence_number, Uint16
       field :reply_length, Uint32
       field :screens, Uint32, :length
       unused 20
       field :screens, XineramaScreenInfo, :list
     end
  end
end
