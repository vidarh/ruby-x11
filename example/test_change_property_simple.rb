#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'X11'

# Connect to the X server
display = X11::Display.new
root = display.default_root
puts "Connected to X server, root window: #{root}"

# Create a test window
window = root  # Just use the root window ID directly to avoid window creation issues
puts "Using root window ID: #{window}"

# Set a test property on the window
property_name = "TEST_PROPERTY"
property_atom = display.atom(property_name)
type_atom = display.atom(:cardinal)  # Use predefined atom for simplicity

# Create a simple 32-bit integer array as test data - 2 integers
values = [123, 456]
test_data = values.pack("L*").bytes  # Pack as 32-bit unsigned integers, then convert to array of bytes
puts "Test data: #{test_data.inspect}, length: #{test_data.length}"

# This will execute the ChangeProperty request
begin
  display.change_property(X11::Form::Replace, window, property_atom, type_atom, 32, test_data)
  puts "Successfully set property '#{property_name}' on window #{window}"
rescue => e
  puts "Error setting property: #{e.class} - #{e.message}"
  puts e.backtrace.join("\n")
end