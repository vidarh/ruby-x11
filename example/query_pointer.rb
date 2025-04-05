#!/usr/bin/env ruby
require_relative '../lib/X11'

display = X11::Display.new
root = display.screens.first.root

# Create a simple window
window = display.create_window(
  100, 100, 400, 300,
  depth: 24,
  values: { X11::Form::CWBackPixel => 0xFFFFFF }
)

# Select input events (pointer motion)
display.select_input(window, X11::Form::PointerMotionMask)

# Map the window (make it visible)
display.map_window(window)

# Wait for window to be visible
sleep(0.5)

puts "Window created. Moving your mouse over the window will display coordinates."
puts "Press Ctrl+C to exit."

# Main event loop
display.run do |event|
  case event
  when X11::Form::MotionNotify
    # Query pointer position relative to window
    pointer = display.query_pointer(window)
    puts "Pointer position:"
    puts "  Window: (#{pointer.win_x}, #{pointer.win_y})"
    puts "  Root:   (#{pointer.root_x}, #{pointer.root_y})"
    puts "  Child:  #{pointer.child == 0 ? 'None' : pointer.child}"
    puts "  Mask:   #{pointer.mask.to_s(16)}"
    puts "  Same screen: #{pointer.same_screen}"
    puts "--------------------"
  end
end
