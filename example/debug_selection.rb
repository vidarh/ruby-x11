#!/usr/bin/env ruby
require_relative '../lib/X11'

# Debug script to diagnose the SetSelectionOwner error

# First, connect to the X server
display = X11::Display.new

# Create a simple window that we'll use as the selection owner
root = display.default_root
window = display.create_window(
  0, 0, 1, 1,
  depth: 24,
  parent: root,
  border_width: 0,
  wclass: X11::Form::InputOutput,
  values: {}
)

# Map the window to make it valid
display.map_window(window)

# Let the server process the request
sleep(0.1)

puts "Created window ID: #{window}"

# Get the atom
atom_name = "CLIPBOARD"  # Using a standard atom that should definitely work
display.intern_atom(false, atom_name)
atom_id = display.atom(atom_name)
puts "Atom #{atom_name} = #{atom_id}"

# Try to set the selection owner
puts "Attempting to set selection owner..."

# Write debug info to a binary file
File.open("/tmp/test_sel.bin", "wb") do |f|
  packet = [
    22,        # opcode (SetSelectionOwner)
    0,         # unused
    4,         # request length (in 4-byte words)
    atom_id,   # selection atom
    window,    # owner window
    0          # timestamp (CurrentTime)
  ]
  
  # Pack into binary format - big endian for 16-bit vals, little endian for 32-bit
  data = [packet[0], packet[1]].pack("CC")
  data += [packet[2]].pack("n")  # 16-bit network order (big endian)
  data += [packet[3], packet[4], packet[5]].pack("LLL")  # 32-bit host order (little endian on x86)
  
  f.write(data)
  puts "Wrote raw packet: #{data.bytes.inspect}"
end

# Use our form based approach
begin
  puts "Using form-based approach..."
  
  # First check the current owner
  original_owner = display.get_selection_owner(atom_id)
  puts "Original selection owner: #{original_owner}"
  
  # Set ourselves as the owner
  display.set_selection_owner(atom_id, window, 0)
  
  # Verify we got it
  new_owner = display.get_selection_owner(atom_id)
  puts "New selection owner: #{new_owner}"
  
  if new_owner == window
    puts "SUCCESS: We got the selection ownership"
  else
    puts "FAILURE: We did not get selection ownership"
  end
rescue => e
  puts "ERROR: #{e.class.name}: #{e.message}"
  puts e.backtrace.join("\n")
end

# Now try direct packet approach
begin
  puts "\nUsing direct packet approach..."
  
  # First check the current owner
  original_owner = display.get_selection_owner(atom_id)
  puts "Original selection owner: #{original_owner}"
  
  # Create the packet manually
  packet = [
    22,        # opcode (SetSelectionOwner)
    0,         # unused
    4,         # request length (in 4-byte words)
    atom_id,   # selection atom
    window,    # owner window
    0          # timestamp (CurrentTime)
  ]
  
  # Pack into binary format
  data = [packet[0], packet[1]].pack("CC")
  data += [packet[2]].pack("n")
  data += [packet[3], packet[4], packet[5]].pack("LLL")
  
  # Write directly to the socket
  display.instance_eval do
    write_packet(data)
  end
  
  # Give a moment for the server to process
  sleep(0.1)
  
  # Verify we got it
  new_owner = display.get_selection_owner(atom_id)
  puts "New selection owner: #{new_owner}"
  
  if new_owner == window
    puts "SUCCESS: We got the selection ownership"
  else
    puts "FAILURE: We did not get selection ownership"
  end
rescue => e
  puts "ERROR: #{e.class.name}: #{e.message}"
  puts e.backtrace.join("\n")
end

# Now try to get a standard atom
puts "\nTrying to set a standard atom..."
std_atom = display.atom("PRIMARY")
puts "Standard PRIMARY atom = #{std_atom}"

begin
  # Get the current owner
  original_owner = display.get_selection_owner(std_atom)
  puts "Original PRIMARY owner: #{original_owner}"
  
  # Set ourselves as the owner
  display.set_selection_owner(std_atom, window, 0)
  
  # Verify we got it
  new_owner = display.get_selection_owner(std_atom)
  puts "New PRIMARY owner: #{new_owner}"
  
  if new_owner == window
    puts "SUCCESS: We got the PRIMARY selection ownership"
  else
    puts "FAILURE: We did not get PRIMARY selection ownership"
  end
rescue => e
  puts "ERROR: #{e.class.name}: #{e.message}"
  puts e.backtrace.join("\n")
end

# Now try to inspect the problem with the _NET_SYSTEM_TRAY_S0 atom
puts "\nDebugging the _NET_SYSTEM_TRAY_S0 atom..."
tray_atom_name = "_NET_SYSTEM_TRAY_S0"
display.intern_atom(false, tray_atom_name)
tray_atom = display.atom(tray_atom_name)
puts "Tray atom #{tray_atom_name} = #{tray_atom}"

begin
  # Get the current owner
  original_owner = display.get_selection_owner(tray_atom)
  puts "Original tray owner: #{original_owner}"
  
  # Set ourselves as the owner
  puts "Setting selection owner for tray atom..."
  display.set_selection_owner(tray_atom, window, 0)
  
  # Verify we got it
  new_owner = display.get_selection_owner(tray_atom)
  puts "New tray owner: #{new_owner}"
  
  if new_owner == window
    puts "SUCCESS: We got the tray selection ownership"
  else
    puts "FAILURE: We did not get tray selection ownership"
  end
rescue => e
  puts "ERROR: #{e.class.name}: #{e.message}"
  puts e.backtrace.join("\n")
end

# Just print a summary and exit
puts "\nDebug testing complete."