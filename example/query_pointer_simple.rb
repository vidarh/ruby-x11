#!/usr/bin/env ruby
require_relative '../lib/X11'

# Create display connection
display = X11::Display.new

# Get root window of first screen
root = display.screens.first.root

puts "Move your mouse around and watch the coordinates update."
puts "Press Ctrl+C to exit."

# Loop and query pointer position every 0.1 seconds
loop do
  pointer = display.query_pointer(root)
  
  system("clear") # Clear terminal
  puts "Pointer position relative to root window:"
  puts "  Root coordinates: (#{pointer.root_x}, #{pointer.root_y})"
  puts "  Window under pointer: #{pointer.child == 0 ? 'None' : pointer.child}"
  puts "  Button/modifier mask: #{pointer.mask.to_s(16)}"
  puts "  Same screen: #{pointer.same_screen}"
  
  sleep(0.1)
end