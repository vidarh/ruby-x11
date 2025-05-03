#!/usr/bin/env ruby
require_relative '../lib/X11'

display = X11::Display.new

puts "Querying Xinerama extension..."

# Check if Xinerama is available
begin
  xinerama_opcode = display.xinerama_opcode
  if !xinerama_opcode
    puts "Xinerama extension not available."
    exit 1
  end
  puts "Xinerama extension found with opcode: #{xinerama_opcode}"
rescue => e
  puts "Error querying Xinerama extension: #{e.message}"
  exit 1
end

# Query version
begin
  version = display.xinerama_query_version
  puts "Xinerama version: #{version.major_version}.#{version.minor_version}"
rescue => e
  puts "Error querying Xinerama version: #{e.message}"
  exit 1
end

# Check if Xinerama is active
begin
  active = display.xinerama_is_active
  puts "Xinerama active: #{active}"
rescue => e
  puts "Error checking if Xinerama is active: #{e.message}"
  exit 1
end

if active
  # Query the screen information
  begin
    screens_info = display.xinerama_query_screens
    puts "\nDetected #{screens_info.screens.length} screen(s):"
    puts "-" * 50
    
    screens_info.screens.each_with_index do |screen, index|
      puts "Screen ##{index + 1}:"
      puts "  Position: (#{screen.x_org}, #{screen.y_org})"
      puts "  Size:     #{screen.width} x #{screen.height}"
      puts "-" * 50
    end
  rescue => e
    puts "Error querying Xinerama screens: #{e.message}"
    exit 1
  end
else
  puts "Xinerama is not active. Unable to query screen information."
end