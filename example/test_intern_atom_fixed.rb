#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'X11'

# Connect to the X server
display = X11::Display.new
puts "Connected to X server"

# Test interning a new atom
atom_name = "TEST_ATOM_#{Time.now.to_i}"
puts "Testing interning a new atom: #{atom_name}"

# This internally uses the InternAtom request
atom_id = display.atom(atom_name)
puts "Successfully interned atom, got ID: #{atom_id}"

# Verify it worked by retrieving the atom name
retrieved_name = display.get_atom_name(atom_id)
puts "Retrieved atom name: #{retrieved_name.inspect}"

if retrieved_name == atom_name
  puts "✓ Atom verification successful"
else
  puts "✗ Atom verification failed: got #{retrieved_name.inspect}, expected #{atom_name.inspect}"
end

puts "Test completed successfully!"