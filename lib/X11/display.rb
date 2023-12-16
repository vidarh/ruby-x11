# FIXME: Temp workaround
require 'stringio'

module X11

  class DisplayError < X11Error; end
  class ConnectionError < X11Error; end
  class AuthorizationError < X11Error; end
  class ProtocolError < X11Error; end

  class Display
    attr_accessor :socket

    # Open a connection to the specified display (numbered from 0) on the specified host
    def initialize(target = ENV['DISPLAY'])
      target =~ /^([\w.-]*):(\d+)(?:.(\d+))?$/
      host, display_id, screen_id = $1, $2, $3
      family = nil

      if host.empty?
        @socket = UNIXSocket.new("/tmp/.X11-unix/X#{display_id}")
        family = :Local
        host = nil
      else
        @socket = TCPSocket.new(host,6000+display_id)
        family = :Internet
      end

      # FIXME
      authorize(host, family, display_id) rescue nil

      @requestseq = 1
      @queue = []

      @extensions = {}

      # Interned atoms
      @atoms = {}
    end

    def event_handler= block
      @event_handler= block
    end

    def display_info
      @internal
    end
    
    def screens
      @internal.screens.map do |s|
        Screen.new(self, s)
      end
    end

    ##
    # The resource-id-mask contains a single contiguous set of bits (at least 18).
    # The client allocates resource IDs for types WINDOW, PIXMAP, CURSOR, FONT,
    # GCONTEXT, and COLORMAP by choosing a value with only some subset of these
    # bits set and ORing it with resource-id-base.

    def new_id
      id = (@xid_next ||= 0)
      @xid_next += 1

      (id & @internal.resource_id_mask) | @internal.resource_id_base
    end

    def read_error data
      error = Form::Error.from_packet(StringIO.new(data))
      STDERR.puts "ERROR: #{error.inspect}"
      raise error.inspect
      error
    end

    def read_reply data
      len = data.unpack("@4L")[0]
      extra = len > 0 ? @socket.read(len*4) : ""
      #STDERR.puts "REPLY: #{data.inspect}"
      #STDERR.puts "EXTRA: #{extra.inspect}"
      data + extra
    end

    def read_event type, data, event_class
      io = StringIO.new(data)
      case type
      # 0 is error, not handled here
      # 1 is reply, not handled here
      when 2  then return Form::KeyPress.from_packet(io)
      when 3  then return Form::KeyRelease.from_packet(io)
      when 4  then return Form::ButtonPress.from_packet(io)
      when 5  then return Form::ButtonRelease.from_packet(io)
      when 6  then return Form::MotionNotify.from_packet(io)
      when 7  then return Form::EnterNotify.from_packet(io)
      when 8  then return Form::LeaveNotify.from_packet(io)
      when 9  then return Form::FocusIn.from_packet(io)
      when 10 then return Form::FocusOut.from_packet(io)
      # FIXME 11: KeymapNotify
      when 12 then return Form::Expose.from_packet(io)
      # FIXME 13: GraphicsExposure
      when 14 then return Form::NoExposure.from_packet(io)
      # FIXME: 15: VisibilityNotify
      when 16 then return Form::CreateNotify.from_packet(io)
      when 17 then return Form::DestroyNotify.from_packet(io)
      when 18 then return Form::UnmapNotify.from_packet(io)
      when 19 then return Form::MapNotify.from_packet(io)
      when 20 then return Form::MapRequest.from_packet(io)
      when 21 then return Form::ReparentNotify.from_packet(io)
      when 22 then return Form::ConfigureNotify.from_packet(io)
      when 23 then return Form::ConfigureRequest.from_packet(io)
      # FIXME: 24: GravityNotify
      # FIXME: 25: ResizeRequest
      # FIXME: 26: CirculateNotify
      # FIXME: 27: CirculateRequest
      when 28 then return Form::PropertyNotify.from_packet(io)
      # FIXME: 29: SelectionClear
      # FIXME: 30: SelectionRequest
      # FIXME: 31: SelectionNotify
      # FIXME: 32: ColormapNotify
      when 33 then return Form::ClientMessage.from_packet(StringIO.new(data))
      # FIXME: 34: MappingNotify
      else
        STDERR.puts "FIXME: Event: #{type}"
        STDERR.puts "EVENT: #{data.inspect}"
        data
      end
    end

    def read_full_packet(len = 32)
      data = @socket.read_nonblock(32)
      return nil if data.nil?
      while data.length < 32
        IO.select([@socket],nil,nil,0.001)
        data.concat(@socket.read_nonblock(32 - data.length))
      end
      return data
    rescue IO::WaitReadable
      return nil
    end

    def read_packet timeout=5.0
      IO.select([@socket],nil,nil, timeout)
      data = read_full_packet(32)
      return nil if data.nil?

      # FIXME: What is bit 8 for? Synthentic?
      type = data.unpack("C").first & 0x7f
      case type
      when 0 then read_error(data)
      when 1 then read_reply(data)
      when 2..34 then read_event(type, data, nil)
      else
        raise ProtocolError, "Unsupported reply type: #{type} #{data.inspect}"
      end
    end

    def write_raw_packet(pkt)
      @requestseq += 1
      @socket.write(pkt)
    end
    
    def write_packet(*args)
      pkt = args.join
      pkt[2..3] = u16(pkt.length/4)
      write_raw_packet(pkt)
    end
    
    def write_request ob
      #p data
      #p [:write_request, @requestseq, ob.class]
      data = ob.to_packet if ob.respond_to?(:to_packet)
      #p [:AddGlyph,data] if ob.is_a?(X11::Form::XRenderAddGlyphs)
      #p [ob.request_length.to_i*4, data.size]
      raise "BAD LENGTH for #{ob.inspect} (#{ob.request_length.to_i*4} ! #{data.size} " if ob.request_length && ob.request_length.to_i*4 != data.size
      write_raw_packet(data)
    end

    def write_sync(data, reply=nil)
      seq = @requestseq
      write_request(data)
      pkt = next_reply(seq)
      return nil if !pkt
      return pkt if pkt.is_a?(X11::Form::Error)
      pp reply
      reply ? reply.from_packet(StringIO.new(pkt)) : pkt
    end

    def peek_packet
      !@queue.empty?
    end

    def next_packet
      @queue.shift || read_packet
    end

    def next_reply(errseq)
      # FIXME: This is totally broken
      while pkt = read_packet
        if pkt.is_a?(String)
          return pkt
        elsif pkt.is_a?(X11::Form::Error) && pkt.sequence_number == errseq
          return pkt
        else
          @queue.push(pkt)
        end
      end
    end
 
    def run
      loop do
        pkt = read_packet
        return if !pkt
        yield(pkt)
      end
    end

    def find_visual(screen, depth, qlass = 4)
      self.display_info.screens[screen].depths.find{|d|
        d.depth == depth }.visuals.find{|v| v.qlass = qlass }
    end

    # Requests
    def create_window(x,y,w,h,
      values: {},
      depth: 32, parent: nil, border_width: 0, wclass: X11::Form::InputOutput, visual: nil
    )
      wid = new_id
      parent ||= screens.first.root

      if visual.nil?
        visual = find_visual(0, depth).visual_id
      end

      values[X11::Form::CWColorMap] ||= create_colormap(0, parent, visual)

      values = values.sort_by{_1[0]}
      mask =   values.inject(0) {|acc,v| (acc | v[0]) }
      values = values.map{_1[1]}
      write_request(
        X11::Form::CreateWindow.new(
          depth, wid, parent,
          x,y,w,h,border_width, wclass, visual, mask, values)
      )
      return wid
    end

    def get_window_attributes(wid)
      write_sync( Form::GetWindowAttributes.new(wid), Form::WindowAttributes )
    end

    def change_window_attributes(wid,
      values: {})
      values = values.sort_by{_1[0]}
      mask =   values.inject(0) {|acc,v| (acc | v[0]) }
      values = values.map{_1[1]}
      write_request(
        X11::Form::ChangeWindowAttributes.new(wid, mask, values)
      )
    end

    def select_input(w, events) = change_window_attributes(w, values: {Form::CWEventMask => events})

    def atom(name)
      name = name.to_sym
      intern_atom(false, name) if !@atoms[name]
      @atoms[name]
    end

    def query_extension(name)
      r = write_sync(X11::Form::QueryExtension.new(name), X11::Form::QueryExtensionReply)
      @extensions[name] = {
        major: r.major_opcode
      }
      r
    end

    def major_opcode(name)
      if !@extensions[name]
        query_extension(name)
      end
      raise "No such extension '#{name}'" if !@extensions[name]
      @extensions[name][:major]
    end
    
    def intern_atom(flag, name)
      reply = write_sync(X11::Form::InternAtom.new(flag, name.to_s),
      X11::Form::InternAtomReply)
      if reply
        @atoms[name.to_sym] = reply.atom
      end
    end

    def get_atom_name(atom)
      reply = write_sync(X11::Form::GetAtomName.new(atom), X11::Form::AtomName)
      reply&.name
    end

    def destroy_window(window) = write_request(X11::Form::DestroyWindow.new(window))
    def get_geometry(drawable) = write_sync(X11::Form::GetGeometry.new(drawable), X11::Form::Geometry)
    
    def get_keyboard_mapping(min_keycode=display_info.min_keycode, count= display_info.max_keycode - min_keycode)
      write_sync(X11::Form::GetKeyboardMapping.new(min_keycode, count), X11::Form::GetKeyboardMappingReply)
    end

    def create_colormap(alloc, window, visual)
      mid = new_id
      write_request(X11::Form::CreateColormap.new(alloc, mid, window, visual))
      mid
    end

    def get_property(window, property, type, offset: 0, length: 4, delete: false)
      property = atom(property) if !property.is_a?(Integer)
      type     = atom_enum(type)
      
      result = write_sync(X11::Form::GetProperty.new(
        delete, window, property, type, offset, length
      ), X11::Form::Property)

      if result && result.format != 0
        case result.format
        when 16
          result.value = result.value.unpack("v")
          result.value = result.value.first if length == 2
        when 32
          result.value = result.value.unpack("V")
          result.value = result.value.first if length == 4
        end
      elsif result
        result.value = nil
      end
      result
    end
    
    def change_property(mode, window, property, type, format, data)
      property = atom(property.to_sym) if property.is_a?(Symbol) || property.is_a?(String)

      mode = open_enum(mode, {replace: 0, prepend: 1, append: 2})
      type = atom_enum(type)
      write_request(X11::Form::ChangeProperty.new(mode, window, property, type, format, data))
    end

    def list_fonts(*args)
      write_sync(X11::Form::ListFonts.new(*args),
        X11::Form::ListFontsReply)
    end

    def open_font(*args)    = write_request(X11::Form::OpenFont.new(*args))
    def change_gc(*args)    = write_request(X11::Form::ChangeGC.new(*args))
    def change_save_set(...)= write_request(X11::Form::ChangeSaveSet.new(...))
    def reparent_window(window, parent, x, y, save: true)
      # You so almost always want this that it should've been a single request
      change_save_set(0, window) if save
      write_request(X11::Form::ReparentWindow.new(window, parent, x,y))
    end
    
    def map_window(*args)   = write_request(X11::Form::MapWindow.new(*args))
    def unmap_window(*args) = write_request(X11::Form::UnmapWindow.new(*args))

    def u8(*args)  = args.pack("c*")
    def u16(*args) = args.pack("v*")
    def u32(*args) = args.pack("V*")
    def atom_enum(val) = open_enum(val, {cardinal: Form::CardinalAtom, atom: Form::AtomAtom, window: Form::WindowAtom})
    def window(*args)
      args.each {|a| raise "Window expected" if a.nil? }
      u32(*args)
    end

    def open_enum(val, map) = (map[val].nil? ? val : map[val])
      
    def set_input_focus(revert_to, focus, time=:now)
      # FIXME: This is an experiment.
      # Upside: Simpler. Downside: Doesn't work server-side.
      # 
      revert_to = open_enum(revert_to, {none: 0, pointer_root: 1, parent: 2})
      focus     = open_enum(focus,     {none: 0, pointer_root: 1 })
      time      = open_enum(time,      {current_time: 0, now: 0})
      write_packet(u8(42,revert_to), u16(3), window(focus), u32(time))
    end
      
    def grab_key(owner_events, grab_window, modifiers, keycode, pointer_mode, keyboard_mode)
      write_request(X11::Form::GrabKey.new(
        owner_events,
        grab_window,
        modifiers,
        keycode,
        pointer_mode  == :async ? 1 : 0,
        keyboard_mode == :async ? 1 : 0
      ))
    end

    def grab_button(owner_events, grab_window, event_mask, pointer_mode,
      keyboard_mode, confine_to, cursor, button, modifiers)
      write_request(X11::Form::GrabButton.new(
        owner_events, grab_window, event_mask,
        pointer_mode == :async ? 1 : 0,
        keyboard_mode == :async ? 1 : 0,
        confine_to.to_i, cursor.to_i, button, modifiers)
      )
    end

    def configure_window(window, x: nil, y: nil, width: nil, height: nil,
      border_width: nil, sibling: nil, stack_mode: nil)

      mask = 0
      values = []

      if x
        mask |= 0x001
        values << x
      end

      if y
        mask |= 0x002
        values << y
      end

      if width
        mask |= 0x004
        values << width
      end

      if height
        mask |= 0x008
        values << height
      end

      if border_width
        mask |= 0x010
        values << border_width
      end

      if sibling
        mask |= 0x020
        values << sibling
      end

      if stack_mode
        mask |= 0x040
        values << case stack_mode
                  when :above then 0
                  when :below then 1
                  when :top_if then 2
                  when :bottom_if then 3
                  when :opposite then 4
                  else raise "Unknown stack_mode #{stack_mode.inspect}"
                  end
      end
      write_request(X11::Form::ConfigureWindow.new(window, mask, values))
    end


    def create_gc(window, foreground: nil, background: nil)
      mask = 0
      args = []

      # FIXME:
      # The rest can be found here:
      # https://tronche.com/gui/x/xlib/GC/manipulating.html#XGCValues
      if foreground
        mask |= 0x04
        args << foreground
      end
      if background
        mask |= 0x08
        args << background
      end

      
      gc = new_id
      write_request(X11::Form::CreateGC.new(gc, window, mask, args))
      gc
    end

    def put_image(*args)   = write_request(X11::Form::PutImage.new(*args))
    def clear_area(*args)  = write_request(X11::Form::ClearArea.new(*args))
    def copy_area(*args)   = write_request(X11::Form::CopyArea.new(*args))
    def image_text8(*args) = write_request(X11::Form::ImageText8.new(*args))
    def image_text16(*args)= write_request(X11::Form::ImageText16.new(*args))
    def poly_fill_rectangle(*args) = write_request(X11::Form::PolyFillRectangle.new(*args))

    def create_pixmap(depth, drawable, w,h)
      pid = new_id
      write_request(X11::Form::CreatePixmap.new(depth, pid, drawable, w,h))
      pid
    end

    # XRender

    def render_opcode
      return @render_opcode if @render_opcode
      @render_opcode = major_opcode("RENDER")
      if @render_opcode
        @render_version = write_sync(X11::Form::XRenderQueryVersion.new(
          @render_opcode,0,11),
          X11::Form::XRenderQueryVersionReply
        )
      end
      @render_opcode
    end

    def render_create_picture(drawable, format, vmask=0, vlist=[])
      pid = new_id
      write_request(X11::Form::XRenderCreatePicture.new(
         render_opcode, pid, drawable, format, vmask, vlist))
      pid
    end

    def render_query_pict_formats
      @render_formats ||= write_sync(
        X11::Form::XRenderQueryPictFormats.new(render_opcode),
        X11::Form::XRenderQueryPictFormatsReply
      )
    end

    def render_find_visual_format(visual)
      # FIXME.
      render_query_pict_formats.screens.map do |s|
        s.depths.map do |d|
          d.visuals.map {|v| v.visual == visual ? v : nil }
        end
      end.flatten.compact.first&.format
    end
    
    def render_find_standard_format(sym)
      # A pox be on the people who made this necessary

      formats = render_query_pict_formats

      case sym
      when :a8
        @a8 ||= formats.formats.find do |f|
          f.type == 1 &&
          f.depth == 8 &&
          f.direct.alpha_mask == 255
        end
      when :rgb24
        @rgb24 ||= formats.formats.find do |f|
          f.type == 1 &&
          f.depth == 24 &&
          f.direct.red == 16 &&
          f.direct.green == 8 &&
          f.direct.blue == 0
        end
      when :argb24
        @argb24 ||= formats.formats.find do |f|
          f.type == 1 &&
          f.depth == 32 &&
          f.direct.alpha == 24 &&
          f.direct.red == 16 &&
          f.direct.green == 8 &&
          f.direct.blue == 0
        end
      else
        raise "Unsupported format (a4/a1 by omission)"
      end
    end

    def render_create_glyph_set(format)
      glyphset = new_id
      write_request(X11::Form::XRenderCreateGlyphSet.new(
        major_opcode("RENDER"),glyphset, format))
      glyphset
    end

    def render_add_glyphs(glyphset, glyphids, glyphinfos, data)
      write_request(X11::Form::XRenderAddGlyphs.new(render_opcode,
        glyphset, Array(glyphids), Array(glyphinfos), data))
    end

    def render_fill_rectangles(op, dst, color, rects)
      color = Form::XRenderColor.new(*color) if color.is_a?(Array)
      rects = rects.map{|r| r.is_a?(Array) ? Form::Rectangle.new(*r) : r}
      write_request(Form::XRenderFillRectangles.new(render_opcode, op, dst, color, rects))
    end

    def render_composite_glyphs32(op, src, dst, fmt, glyphset, srcx,srcy, *elts)
      write_request(X11::Form::XRenderCompositeGlyphs32.new(
        render_opcode,
        op, src, dst, fmt,
        glyphset,
        srcx, srcy,
        elts.map {|e| e.is_a?(Array) ? Form::GlyphElt32.new(*e) : e }
      ))
    end

    def render_create_solid_fill(*color)
      if color.length == 1 && color.is_a?(Form::XRenderColor)
        color = color[0]
      else
        color = Form::XRenderColor.new(*color)
      end
      fill = new_id
      write_request(Form::XRenderCreateSolidFill.new(render_opcode,fill,color))
      fill
    end

    private

    def authorize(host, family, display_id)
      auth = Auth.new
      auth_info = auth.get_by_hostname(host||"localhost", family, display_id)

      if auth_info
        auth_name, auth_data = auth_info.auth_name, auth_info.auth_data
      else
        auth_name = ""
        auth_data = ""
      end
      p [auth_name, auth_data]

      handshake = Form::ClientHandshake.new(
        Protocol::BYTE_ORDER,
        Protocol::MAJOR,
        Protocol::MINOR,
        auth_name,
        auth_data
      )

      @socket.write(handshake.to_packet)

      data = @socket.read(1)
      raise AuthorizationError, "Failed to read response from server" if !data

      case data.unpack("w").first
      when X11::Auth::FAILED
        len, major, minor, xlen = @socket.read(7).unpack("CSSS")
        reason = @socket.read(xlen * 4)
        reason = reason[0..len]
        raise AuthorizationError, "Connection to server failed -- (version #{major}.#{minor}) #{reason}"
      when X11::Auth::AUTHENTICATE
        raise AuthorizationError, "Connection requires authentication"
      when X11::Auth::SUCCESS
        @socket.read(7) # skip unused bytes
        @internal = Form::DisplayInfo.from_packet(@socket)
      else
        raise AuthorizationError, "Received unknown opcode #{type}"
      end
    end

    def to_s
      "#<X11::Display:0x#{object_id.to_s(16)} screens=#{@internal.screens.size}>"
    end
  end
end
