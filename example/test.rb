require 'rubygems'
require 'skrift'
require 'bundler'
require 'chunky_png'
Bundler.setup(:default, :development)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'X11'


dpy = display = X11::Display.new
screen = dpy.screens.first
root = screen.root

window = X11::Window.create(dpy, 
  0, 0, # x,y
  1000, 600, # w,h
  # FIXME: WTH isn't depth: 32 working here?
  depth: 24,
  values: {
    X11::Form::CWBackPixel => 0x0,
    X11::Form::CWEventMask =>
      (X11::Form::SubstructureNotifyMask |
       X11::Form::StructureNotifyMask    | ## Move
       X11::Form::ExposureMask           |
       X11::Form::KeyPressMask           |
       X11::Form::ButtonPressMask)
   }
)
#dpy.next_packet
#exit(0)


def set_window_opacity(window, opacity)
  window.change_property(
    :replace,
    "_NET_WM_WINDOW_OPACITY",
    :cardinal, 32,
    [(0xffffffff * opacity).to_i].pack("V").unpack("C*")
  )
end


set_window_opacity(window, 0.8)

#p dpy.display_info

#reply = dpy.query_extension("XKEYBOARD")

$kmap = nil
def update_keymap(dpy)
  reply = dpy.get_keyboard_mapping


  if reply
    $kmap = reply.keysyms.map do |c|
      if c == 0
        nil
      elsif X11::KeySyms[c]
        X11::KeySyms[c]
      elsif c < 0x100
        c.chr(Encoding::ISO_8859_1)
      elsif c.between?(0xffb0, 0xffb9)
        "KP_#{c-0xffb0}".to_sym
      elsif c.between?(0xffbe, 0xffe0)
        "F#{c-0xffbe+1}".to_sym
      elsif c.between?(0xff08, 0xffff)
        # FIIXME:
        raise "keyboard_#{c.to_s(16)}".to_s
      elsif c.between?(0x01000100, 0x0110FFFF)
        (c-0x01000100).
        chr(Encoding::UTF_32) rescue c.to_s(16)
      else
        raise "unknown_#{c.to_s(16)}"
      end
    end.each_slice(reply.keysyms_per_keycode).to_a
    #ks = ks.map {|s| s.compact.sort_by{|x| x.to_s}.uniq }.to_a # This is for testing/ease of reading only
    p $kmap[47-dpy.display_info.min_keycode]
  end
end


def lookup_keysym(dpy,  event)
  update_keymap(dpy) if !$kmap
  p $kmap[event.detail-dpy.display_info.min_keycode]
end

puts "Mapping"
window.map

$gc = gc = window.create_gc(foreground: 0xff0000)
$gc2 = window.create_gc(foreground: 0xffffff, background: 0x444444)
$gc3 = window.create_gc


puts "Main loop"

#p dpy.list_fonts(10,  "*7x13*").names.map(&:to_s)

fid = dpy.new_id
dpy.open_font(fid, "-misc-fixed-bold-r-normal--13-120-75-75-c-70-iso10646-1")
#"-bitstream-courier 10 pitch-medium-r-normal--0-0-0-0-m-0-iso10646-1")
dpy.change_gc($gc2, X11::Form::FontMask, [fid])

$png = ChunkyPNG::Image.from_file('genie.png')

$data = ""
$png.pixels.each do |px|
  str = [px].pack("N")
  if str[3] == "\x00"
    $data << "\0\0\0\0".force_encoding("ASCII-8BIT")
  else
    $data << str[2] << str[1] << str[0] << str[3]
  end
end

#$f = Font.load("/usr/share/fonts/truetype/tlwg/Umpush-BoldOblique.ttf")
$f = Font.load("/usr/share/fonts/truetype/tlwg/Garuda.ttf")
#$f = Font.load("resources/FiraGO-Regular.ttf")

$sft = SFT.new($f)
$sft.x_scale = 15
$sft.y_scale = 15
$glyphcache = {}
def render_glyph(window, x,y, ch)
  gid = $sft.lookup(ch.ord)
  mtx = $sft.gmetrics(gid)
  data = $glyphcache[gid]
  if !data
    img = Image.new(mtx.min_width, mtx.min_height) #(mtx .min_width + 3) & ~3, mtx.min_height)
    if !$sft.render(gid, img)
      raise "Unable to render #{gid}\n"
    end
 #   p img
    data = img.pixels.map {|px|
      "\0\0"+px.chr+"\0" #+ "\0\0\0"
    }.join.b
    $glyphcache[gid] = data
  end
  depth = 24
#  p data
#p img
#  p ch
   window.put_image(
    :ZPixmap, $gc2,
    mtx.min_width,mtx.min_height,
    x, y - mtx.y_offset, 0, depth, data
  )
  mtx.advance_width
end

def render_str(window, x,y, str)
  str.each_byte do |ch|
    off = render_glyph(window, x, y, ch.chr)
    x+= off
  end
end

def redraw(window, gc)
  window.poly_fill_rectangle(gc, [20,20, 60, 80])
  window.clear_area(false, 30, 30, 5, 5)
  window.image_text16($gc2, 30, 70, "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ")
  #"\u25f0\u25ef Hello World")
  window.put_image(
    :ZPixmap, $gc2,
    $png.width, $png.height, 80, 120, 0, 24, $data
  )
  render_str(window, 30,90, 'HelloWorld')
end

loop do
  pkt = display.next_packet
  if pkt
    p pkt
    redraw(window, gc) if pkt.is_a?(X11::Form::Expose)

    if pkt.is_a?(X11::Form::KeyPress)
      lookup_keysym(dpy,pkt)
    end
  end
end
