require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'X11'

display = X11::Display.new
screen = display.screens.first
root = screen.root
wid = display.new_id
display.write_request(X11::Form::CreateWindow.new(
  screen.root_depth,
  wid,
  root,
  0,  #x
  0,  #y
  200,#w
  200,#h
  0,
  X11::Form::InputOutput,
  X11::Form::CopyFromParent,
  X11::Form::CWBackPixel | X11::Form::CWEventMask,
  [0xff8844, # RGB background
   X11::Form::SubstructureNotifyMask |
#   X11::Form::StructureNotifyMask    | ## Move
   X11::Form::ExposureMask           |
   X11::Form::KeyPressMask           |
   X11::Form::ButtonPressMask
  ]
))
puts "Mapping"
display.write_request(X11::Form::MapWindow.new(wid))
# Creating GC
gc = display.new_id
display.write_request(X11::Form::CreateGC.new(
  gc, screen.root,
  X11::Form::ForegroundMask,
  [0xff0000,  # RGB foreground
  ]
))

$gc2 = display.new_id
display.write_request(X11::Form::CreateGC.new(
  $gc2,
  screen.root,
  X11::Form::ForegroundMask|X11::Form::BackgroundMask,
  [0xffffff,  # RGB foreground
   0x444444,
  ]
))

puts "Main loop"
p gc

# This will wait for a reply
p display.write_sync(X11::Form::ListFonts.new(10,  "*7x13*"),
  X11::Form::ListFontsReply).names.map(&:to_s)

fid = display.new_id
display.write_request(X11::Form::OpenFont.new(fid, "7x13"))
display.write_request(X11::Form::ChangeGC.new($gc2, X11::Form::FontMask, [fid]))


def redraw(display, wid, gc)
  p [:redraw, gc]
  display.write_request(X11::Form::PolyFillRectangle.new(
    wid, gc,
    [X11::Form::Rectangle.new(20,20, 60, 80)]
  ))

  display.write_request(X11::Form::ClearArea.new( false, wid, 30, 30, 5, 5))
  display.write_request(X11::Form::ImageText8.new(wid, $gc2, 30, 70, "Hello World"))
end

loop do
  pkt = display.next_packet
  if pkt
    p pkt
    redraw(display, wid, gc)
  end
end

