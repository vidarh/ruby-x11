#!/usr/bin/env ruby
require_relative '../lib/X11'

# A *minimal* System Tray implementation for X11 using the ruby-x11 library
# Based on the freedesktop.org System Tray Protocol Specification
# http://standards.freedesktop.org/systemtray-spec/systemtray-spec-latest.html
#
# **CAUTION**: This is written entirely by Claude, except for this comment,
# and has not been thoroughly checked. It works, but may contain all kinds of
# stupidity that's not necessary... A future version will clean this up.

class SystemTray
  # Constants for system tray
  SYSTEM_TRAY_ORIENTATION_HORZ = 0
  SYSTEM_TRAY_ORIENTATION_VERT = 1
  
  # X11 atom constants from X11::Form::Atoms
  STRING_ATOM = 31  # X11::Form::Atoms::STRING
  
  # Predefined XEMBED message codes
  XEMBED_EMBEDDED_NOTIFY = 0
  XEMBED_WINDOW_ACTIVATE = 1
  XEMBED_WINDOW_DEACTIVATE = 2
  XEMBED_REQUEST_FOCUS = 3
  XEMBED_FOCUS_IN = 4
  XEMBED_FOCUS_OUT = 5
  XEMBED_FOCUS_NEXT = 6
  XEMBED_FOCUS_PREV = 7
  
  # Flags for _XEMBED_INFO
  XEMBED_MAPPED = (1 << 0)
  
  # Version for the XEMBED protocol
  XEMBED_VERSION = 0
  
  # Default icon size
  ICON_DEFAULT_SIZE = 24
  
  def initialize(panel_width, panel_height, screen_number = 0, debug = true, dark_mode = false)
    @panel_width = panel_width
    @panel_height = panel_height
    @screen_number = screen_number
    @embedded_icons = {}  # Map of window IDs to icon objects
    @tray_atom = nil
    @display = nil
    @tray_window = nil
    @initialized = false
    @orientation = SYSTEM_TRAY_ORIENTATION_HORZ
    @debug = debug
    @dark_mode = dark_mode
    
    # Log settings if debug enabled
    puts "Initializing SystemTray with size #{panel_width}x#{panel_height}, screen #{screen_number}" if @debug
    puts "Dark mode enabled" if @debug && @dark_mode
  end
  
  def initialize_tray
    # Connect to X display
    @display = X11::Display.new
    
    # Create the tray window with additional properties needed for it to be a valid selection owner
    screen = @display.screens.first
    root = @display.default_root
    
    # Configure appropriate colors for light/dark mode
    if @dark_mode
      bg_color = screen.black_pixel
      border_color = 0x444444  # Dark gray border
    else
      bg_color = screen.white_pixel
      border_color = screen.black_pixel
    end
    
    @tray_window = @display.create_window(
      100, 100,                 # position - make it visible for debugging 
      @panel_width, @panel_height, # size
      border_width: 1,          # Add a visible border for debugging
      parent: root,             # Explicitly specify the root window as parent
      depth: screen.root_depth, # Use the root depth to avoid format issues
      wclass: X11::Form::InputOutput,
      values: {
        X11::Form::CWBackPixel => bg_color,        # Background color based on mode
        X11::Form::CWBorderPixel => border_color,  # Border color based on mode
        X11::Form::CWEventMask => X11::Form::StructureNotifyMask | 
                                X11::Form::SubstructureNotifyMask | 
                                X11::Form::SubstructureRedirectMask |
                                X11::Form::ExposureMask |
                                X11::Form::PropertyChangeMask,
        X11::Form::CWOverrideRedirect => 1  # Prevent window manager from managing this window
      }
    )
    
    puts "Created tray window with ID: #{@tray_window}" if @debug
    
    # Map the window to make it visible and valid for selection ownership
    @display.map_window(@tray_window)
    
    puts "Initializing atoms..." if @debug
    
    # Create the selection atom name (screen specific)
    selection_atom_name = "_NET_SYSTEM_TRAY_S#{@screen_number}"
    
    # Initialize our needed atoms
    @atoms = {
      "MANAGER" => @display.atom("MANAGER"),
      "_NET_SYSTEM_TRAY_OPCODE" => @display.atom("_NET_SYSTEM_TRAY_OPCODE"),
      "_NET_SYSTEM_TRAY_MESSAGE_DATA" => @display.atom("_NET_SYSTEM_TRAY_MESSAGE_DATA"),
      "_NET_SYSTEM_TRAY_ORIENTATION" => @display.atom("_NET_SYSTEM_TRAY_ORIENTATION"),
      "_XEMBED_INFO" => @display.atom("_XEMBED_INFO"),
      "_XEMBED" => @display.atom("_XEMBED")
    }
    
    # Get the tray selection atom
    @tray_atom = @display.atom(selection_atom_name)
    
    # Attempt to acquire ownership of the system tray selection
    # CurrentTime = 0 in X11
    timestamp = 0
    
    # Set ourselves as the owner
    @display.set_selection_owner(@tray_atom, @tray_window, timestamp)
    
    # Give a moment for the server to process
    sleep(0.1)
    
    # Check if we really got the selection
    owner = @display.get_selection_owner(@tray_atom)
    if owner == @tray_window
      puts "Successfully acquired system tray selection ownership" if @debug
    else
      puts "Failed to acquire system tray selection ownership"
      if owner != 0
        puts "Another system tray is likely running"
        return false
      end
    end
    
    # Announce that we're the system tray manager by sending a MANAGER client message
    send_manager_notification
    
    # Set properties on our tray window
    set_tray_orientation(SYSTEM_TRAY_ORIENTATION_HORZ)  # Default to horizontal
    
    # Set theme-related properties that might help client applications detect dark mode
    if @dark_mode
      # Set some common properties that applications might check for dark mode
      # GTK_THEME_VARIANT property (used by some GTK applications)
      @atoms["_GTK_THEME_VARIANT"] = @display.atom("_GTK_THEME_VARIANT")
      
      # Create dark string with proper padding to 4 byte boundary
      dark_str = "dark".unpack("C*")
      # Padding to multiple of 4 bytes
      while (dark_str.length % 4) != 0
        dark_str.push(0)  # Add null padding
      end
      
      @display.change_property(
        X11::Form::Replace,
        @tray_window,
        @atoms["_GTK_THEME_VARIANT"],
        STRING_ATOM,  # Use STRING atom type (31)
        8,  # 8 bits per element
        dark_str
      )
      
      # QT_STYLE_OVERRIDE property (used by some Qt applications)
      @atoms["QT_STYLE_OVERRIDE"] = @display.atom("QT_STYLE_OVERRIDE")
      
      # Create fusion string with proper padding to 4 byte boundary
      fusion_str = "Fusion".unpack("C*")
      # Padding to multiple of 4 bytes
      while (fusion_str.length % 4) != 0
        fusion_str.push(0)  # Add null padding
      end
      
      @display.change_property(
        X11::Form::Replace,
        @tray_window,
        @atoms["QT_STYLE_OVERRIDE"],
        STRING_ATOM, # Use STRING atom type (31)
        8,
        fusion_str
      )
      
      puts "Set dark mode theme properties" if @debug
    end
    
    @initialized = true
    @display.map_window(@tray_window)
    true
  end
  
  def send_manager_notification
    # Send MANAGER client message to the root window to announce our presence
    # According to the System Tray Protocol:
    # - window = root window
    # - message_type = MANAGER
    # - format = 32
    # - data[0] = timestamp when the manager selection was acquired
    # - data[1] = selection atom (_NET_SYSTEM_TRAY_Sn)
    # - data[2] = manager window
    
    root = @display.default_root
    timestamp = 0  # CurrentTime = 0 in X11
    
    # Data array with trailing zeros
    event_data = [timestamp, @tray_atom, @tray_window, 0, 0]
    
    # Send the client message
    @display.client_message(
      window: root,
      type: @atoms["MANAGER"],
      format: 32,
      destination: root,
      mask: X11::Form::StructureNotifyMask,
      data: event_data
    )
  end
  
  def set_tray_orientation(orientation)
    # Set the orientation property on our tray window
    @orientation = orientation
    
    # Create binary representation of the orientation value
    data = [orientation].pack("L").unpack("C*")
    
    # Set the property on our window
    @display.change_property(
      X11::Form::Replace,
      @tray_window,
      @atoms["_NET_SYSTEM_TRAY_ORIENTATION"],
      X11::Form::CardinalAtom,
      32,
      data
    )
  end
  
  def handle_client_message(event)
    begin
      # Check if window is our tray window or one of our icon windows
      # This helps filter out messages not meant for us
      is_our_window = (event.window == @tray_window) || @embedded_icons.key?(event.window)
      
      if event.type == @atoms["_NET_SYSTEM_TRAY_OPCODE"] && event.format == 32
        puts "Received _NET_SYSTEM_TRAY_OPCODE message to window #{event.window}"
        
        # For opcode messages, data layout is:
        # l[0] = timestamp
        # l[1] = opcode (SYSTEM_TRAY_REQUEST_DOCK = 0)
        # l[2] = icon window ID (for dock requests)
        # l[3] = data1
        # l[4] = data2
        
        # Extract data values (using little-endian format)
        data_values = event.data.unpack("L5")
        
        if data_values && data_values.length >= 3
          timestamp = data_values[0]
          opcode = data_values[1]
          
          case opcode
          when 0  # SYSTEM_TRAY_REQUEST_DOCK
            icon_window = data_values[2]
            puts "Received dock request for window: #{icon_window}"
            dock_icon(icon_window)
          when 1  # SYSTEM_TRAY_BEGIN_MESSAGE
            # Balloon message handling - would need to create a popup window
            puts "Begin message received, data: #{data_values.inspect}"
          when 2  # SYSTEM_TRAY_CANCEL_MESSAGE
            # Cancel balloon message
            puts "Cancel message received, message ID: #{data_values[2]}" 
          end
        end
      elsif event.type == @atoms["_XEMBED"] && event.format == 32
        # Extract XEMBED protocol data
        data_values = event.data.unpack("L5")
        
        if data_values && data_values.length >= 3
          timestamp = data_values[0]
          message = data_values[1]
          detail = data_values[2]
          
          puts "Received XEMBED message: #{message}, detail: #{detail} for window #{event.window}"
          
          case message
          when XEMBED_REQUEST_FOCUS
            # Icon is requesting focus
            puts "Icon requested focus: #{event.window}"
            # We could potentially focus the application here
          when XEMBED_FOCUS_IN, XEMBED_FOCUS_OUT
            # Focus events - could be used to highlight active icon
            puts "Focus #{message == XEMBED_FOCUS_IN ? 'in' : 'out'} event for window #{event.window}"
          end
        end
      elsif is_our_window
        # Other client messages that might be relevant
        puts "Received client message of type #{@display.get_atom_name(event.type) || event.type} to window #{event.window}"
      end
    rescue => e
      # Error handling to prevent crashes on malformed messages
      puts "Error processing client message: #{e.message}"
      puts e.backtrace.join("\n") if @debug
    end
  end
  
  def dock_icon(icon_window)
    # Don't dock the same window twice
    return if @embedded_icons.key?(icon_window)
    
    puts "Attempting to dock icon window #{icon_window}" if @debug
    
    # Check if the window exists
    attributes = @display.get_window_attributes(icon_window)
    if !attributes
      puts "Window #{icon_window} doesn't exist or can't be accessed"
      return
    end
    
    # Add event mask to the icon window
    event_mask = X11::Form::StructureNotifyMask | X11::Form::PropertyChangeMask
    @display.change_window_attributes(
      icon_window,
      values: {
        X11::Form::CWEventMask => event_mask
      }
    )
    
    # Create an icon object to track this window with default size
    icon = {
      "window" => icon_window,
      "width" => ICON_DEFAULT_SIZE,
      "height" => ICON_DEFAULT_SIZE,
      "visible" => false
    }
    
    # Try to get geometry info for better sizing
    begin
      geometry = @display.get_geometry(icon_window)
      if geometry
        puts "Icon geometry: #{geometry.width}x#{geometry.height}" if @debug
        
        # Check for tiny icons (some apps create 1x1 icons)
        if geometry.width < 4 || geometry.height < 4
          puts "Ignoring very small icon size (#{geometry.width}x#{geometry.height}), using default" if @debug
          # Keep the default size
        else
          # Use the actual geometry
          icon["width"] = geometry.width
          icon["height"] = geometry.height
        end
      end
    rescue => e
      puts "Error getting geometry: #{e.message}" if @debug
      # Keep default size
    end
    
    # Resize the icon window to match our desired size
    @display.configure_window(
      icon_window,
      width: icon["width"],
      height: icon["height"]
    )
    
    # Reparent the icon window to our tray window (this is the actual embedding)
    @display.reparent_window(icon_window, @tray_window, 0, 0)
    
    # If dark mode is enabled, try to set some properties on the icon window
    # to encourage applications to use dark mode icons if available
    if @dark_mode
      begin
        # Set a hint that we're in dark mode (some apps might check for this)
        @atoms["_XEMBED_INFO_DARKMODE"] = @display.atom("_XEMBED_INFO_DARKMODE")
        @display.change_property(
          X11::Form::Replace,
          icon_window,
          @atoms["_XEMBED_INFO_DARKMODE"],
          X11::Form::CardinalAtom,
          32,
          [1]  # 1 = dark mode enabled
        )
        
        # Set GTK dark mode hint on the icon window too
        @atoms["_GTK_THEME_VARIANT"] = @display.atom("_GTK_THEME_VARIANT")
        
        # Create dark string with proper padding to 4 byte boundary
        dark_str = "dark".unpack("C*")
        # Padding to multiple of 4 bytes
        while (dark_str.length % 4) != 0
          dark_str.push(0)  # Add null padding
        end
        
        @display.change_property(
          X11::Form::Replace,
          icon_window,
          @atoms["_GTK_THEME_VARIANT"],
          STRING_ATOM,  # Use STRING atom type (31)
          8,  # 8 bits per element
          dark_str
        )
        
        puts "Set dark mode hints on icon window #{icon_window}" if @debug
      rescue => e
        puts "Error setting dark mode properties on icon: #{e.message}" if @debug
      end
    end
    
    # Get the XEMBED_INFO property
    get_xembed_info(icon)
    
    # Store the icon in our tracking map
    @embedded_icons[icon_window] = icon
    
    # Send XEMBED message to tell the icon it's embedded
    send_xembed_message(
      icon_window,
      XEMBED_EMBEDDED_NOTIFY,
      0,  # detail
      @tray_window,  # embed_info_window
      XEMBED_VERSION
    )
    
    # Always make the icon visible since reparenting may have unmapped it
    @display.map_window(icon_window)
    icon["visible"] = true
    puts "Mapped icon window #{icon_window}" if @debug
    
    # Make sure our tray window is visible
    @display.map_window(@tray_window)
    
    # Update the layout of all icons
    layout_icons
  end
  
  def get_xembed_info(icon)
    return unless icon  # Safety check
    window_id = icon["window"]
    
    begin
      puts "Getting XEMBED_INFO for window #{window_id}" if @debug
      
      # First verify window still exists
      begin
        attributes = @display.get_window_attributes(window_id)
        unless attributes
          puts "Window #{window_id} no longer exists" if @debug
          return false
        end
      rescue => e
        puts "Error checking window attributes: #{e.message}" if @debug
        return false
      end
      
      # Get XEMBED_INFO property from the icon window
      begin
        result = @display.get_property(
          window_id,
          @atoms["_XEMBED_INFO"],
          @atoms["_XEMBED_INFO"]
        )
      rescue => e
        puts "Error getting XEMBED_INFO property: #{e.message}" if @debug
        # Default to mapped if we can't get the property
        icon["xembed_version"] = XEMBED_VERSION
        icon["xembed_flags"] = XEMBED_MAPPED
        @display.map_window(window_id) rescue nil
        icon["visible"] = true
        return true
      end
      
      # If we got a valid result with data
      if result && result.value && result.value.is_a?(Array) && result.value.length >= 2
        # Extract version and flags
        version = result.value[0]
        flags = result.value[1]
        
        puts "XEMBED_INFO: version=#{version}, flags=#{flags}" if @debug
        
        # Store in our icon object
        icon["xembed_version"] = version
        icon["xembed_flags"] = flags
        
        # Check if the icon wants to be mapped (XEMBED_MAPPED = bit 0)
        if (flags & XEMBED_MAPPED) != 0
          puts "XEMBED_MAPPED flag is set, mapping window" if @debug
          @display.map_window(window_id) rescue nil
          icon["visible"] = true
        else
          puts "XEMBED_MAPPED flag is not set" if @debug
        end
      else
        # Even without XEMBED_INFO, we should map the window by default
        # This helps with clients that don't set the property correctly
        puts "No valid XEMBED_INFO property found, using defaults" if @debug
        icon["xembed_version"] = XEMBED_VERSION
        icon["xembed_flags"] = XEMBED_MAPPED  # Default to mapped
        
        # Map the window anyway - most applications expect this
        @display.map_window(window_id) rescue nil
        icon["visible"] = true
      end
      
      return true
    rescue => e
      puts "Unexpected error in get_xembed_info: #{e.message}" if @debug
      return false
    end
  end
  
  def send_xembed_message(window, message, detail, data1, data2)
    # Send an XEMBED client message to a specific window
    timestamp = Time.now.to_i
    
    # Send the message
    @display.client_message(
      window: window,
      type: @atoms["_XEMBED"],
      format: 32,
      destination: window,
      mask: 0, # NoEventMask
      data: [timestamp, message, detail, data1, data2]
    )
  end
  
  def layout_icons
    # Calculate the layout of icons in the tray
    puts "Laying out icons, count: #{@embedded_icons.size}" if @debug
    
    # Layout logic depends on orientation
    spacing = 2  # pixels between icons
    padding = 2  # padding inside tray
    
    # Calculate required space
    visible_icons = @embedded_icons.values.select { |icon| icon["visible"] }
    
    if @orientation == SYSTEM_TRAY_ORIENTATION_HORZ
      # Horizontal layout - calculate total width needed
      total_width = visible_icons.inject(0) { |sum, icon| sum + icon["width"] }
      total_width += (visible_icons.size - 1) * spacing if visible_icons.size > 1
      total_width += padding * 2  # Add padding on both sides
      
      # Use either the calculated width or minimum panel width, whichever is larger
      actual_width = [total_width, @panel_width].max
      actual_height = @panel_height
    else
      # Vertical layout - calculate total height needed
      total_height = visible_icons.inject(0) { |sum, icon| sum + icon["height"] }
      total_height += (visible_icons.size - 1) * spacing if visible_icons.size > 1
      total_height += padding * 2  # Add padding on both sides
      
      # Use either the calculated height or minimum panel height, whichever is larger
      actual_width = @panel_width
      actual_height = [total_height, @panel_height].max
    end
    
    # Resize the tray window if needed
    @display.configure_window(@tray_window, width: actual_width, height: actual_height)
    
    # Position icons
    if @orientation == SYSTEM_TRAY_ORIENTATION_HORZ
      # Horizontal layout
      x = padding
      visible_icons.each do |icon|
        # Get the available panel height
        panel_height = actual_height - (padding * 2)
        
        # Handle tiny icons (height < 4 or width < 4) by using default size
        if icon["height"] < 4 || icon["width"] < 4
          puts "Found tiny icon (#{icon["width"]}x#{icon["height"]}), will scale up" if @debug
          # Use the default icon size instead
          icon["width"] = ICON_DEFAULT_SIZE
          icon["height"] = ICON_DEFAULT_SIZE
        end
        
        # Get the aspect ratio for scaling
        aspect_ratio = icon["width"].to_f / icon["height"]
        
        # Check if the icon is smaller than the panel height
        if icon["height"] < panel_height
          puts "Icon height (#{icon["height"]}) is smaller than panel (#{panel_height}), scaling up" if @debug
          # Scale to fill height of the panel
          icon_height = panel_height
          icon_width = (icon_height * aspect_ratio).to_i
        else
          # Keep original size if larger than panel
          icon_height = icon["height"]
          icon_width = icon["width"]
        end
        
        # Center vertically
        y = (actual_height - icon_height) / 2
        
        puts "Positioning icon #{icon["window"]} at x=#{x}, y=#{y}, size=#{icon_width}x#{icon_height}" if @debug
        
        # Move and resize the icon window
        @display.configure_window(
          icon["window"],
          x: x,
          y: y,
          width: icon_width,
          height: icon_height
        )
        
        x += icon_width + spacing
      end
    else
      # Vertical layout
      y = padding
      visible_icons.each do |icon|
        # Get the available panel width
        panel_width = actual_width - (padding * 2)
        
        # Handle tiny icons (height < 4 or width < 4) by using default size
        if icon["height"] < 4 || icon["width"] < 4
          puts "Found tiny icon (#{icon["width"]}x#{icon["height"]}), will scale up" if @debug
          # Use the default icon size instead
          icon["width"] = ICON_DEFAULT_SIZE
          icon["height"] = ICON_DEFAULT_SIZE
        end
        
        # Get the aspect ratio for scaling
        aspect_ratio = icon["height"].to_f / icon["width"]
        
        # Check if the icon is smaller than the panel width
        if icon["width"] < panel_width
          puts "Icon width (#{icon["width"]}) is smaller than panel (#{panel_width}), scaling up" if @debug
          # Scale to fill width of the panel
          icon_width = panel_width
          icon_height = (icon_width * aspect_ratio).to_i
        else
          # Keep original size if larger than panel
          icon_width = icon["width"]
          icon_height = icon["height"]
        end
        
        # Center horizontally
        x = (actual_width - icon_width) / 2
        
        puts "Positioning icon #{icon["window"]} at x=#{x}, y=#{y}, size=#{icon_width}x#{icon_height}" if @debug
        
        # Move and resize the icon window
        @display.configure_window(
          icon["window"],
          x: x,
          y: y,
          width: icon_width,
          height: icon_height
        )
        
        y += icon_height + spacing
      end
    end
    
    # Make sure all windows are mapped
    visible_icons.each do |icon|
      @display.map_window(icon["window"])
    end
    
    # Make sure our changes are sent to the server
    @display.flush
  end
  
  def handle_icon_destroyed(window)
    # Called when an icon window is destroyed
    if @embedded_icons.key?(window)
      @embedded_icons.delete(window)
      layout_icons
    end
  end
  
  def handle_icon_configure(window, width, height)
    # Called when an icon window changes size
    if @embedded_icons.key?(window)
      @embedded_icons[window]["width"] = width
      @embedded_icons[window]["height"] = height
      layout_icons
    end
  end
  
  def handle_icon_map(window)
    # Called when an icon window is mapped (made visible)
    if @embedded_icons.key?(window)
      @embedded_icons[window]["visible"] = true
      layout_icons
    end
  end
  
  def handle_icon_unmap(window)
    # Called when an icon window is unmapped (hidden)
    if @embedded_icons.key?(window)
      @embedded_icons[window]["visible"] = false
      layout_icons
    end
  end
  
  def process_events
    # Main event processing loop
    puts "Processing systray events (press Ctrl+C to exit)..."
    
    @display.run do |event|
      case event
      when X11::Form::ClientMessage
        handle_client_message(event)
      when X11::Form::DestroyNotify
        handle_icon_destroyed(event.window) if event.window != @tray_window
      when X11::Form::ConfigureNotify
        handle_icon_configure(event.window, event.width, event.height) if event.window != @tray_window
      when X11::Form::MapNotify
        handle_icon_map(event.window) if event.window != @tray_window
      when X11::Form::UnmapNotify
        handle_icon_unmap(event.window) if event.window != @tray_window
      when X11::Form::PropertyNotify
        # Handle property change notifications - safely
        begin
          if @embedded_icons.key?(event.window)
            # If the _XEMBED_INFO property changed, update our info
            if event.atom == @atoms["_XEMBED_INFO"]
              puts "XEMBED_INFO property changed for #{event.window}" if @debug
              
              # First check if the window still exists
              begin
                attributes = @display.get_window_attributes(event.window)
                if attributes
                  get_xembed_info(@embedded_icons[event.window])
                  layout_icons
                else
                  puts "Window #{event.window} no longer exists, removing from tracked icons" if @debug
                  @embedded_icons.delete(event.window)
                  layout_icons
                end
              rescue => e
                # Window likely destroyed
                puts "Error checking window attributes: #{e.message}" if @debug
                @embedded_icons.delete(event.window)
                layout_icons
              end
            end
          end
        rescue => e
          puts "Error handling property notification: #{e.message}" if @debug
        end
      end
    end
  end
  
  def cleanup
    # Release the selection ownership
    if @initialized && @display
      # Set owner to None (0) to release the selection
      @display.set_selection_owner(@tray_atom, 0, 0)
      puts "Released system tray selection ownership" if @debug
      
      # Destroy tray window
      @display.destroy_window(@tray_window)
      puts "Destroyed tray window" if @debug
      
      # Close display - handled by ruby-x11's at_exit
    end
  end
end

# Simple example usage
if __FILE__ == $0
  require 'optparse'
  
  options = {
    width: 240,
    height: 30,
    screen: 0,
    debug: false,
    dark_mode: false
  }
  
  # Parse command line options
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    
    opts.on("-w", "--width WIDTH", Integer, "Width of the tray (default: #{options[:width]})") do |w|
      options[:width] = w
    end
    
    opts.on("-h", "--height HEIGHT", Integer, "Height of the tray (default: #{options[:height]})") do |h|
      options[:height] = h
    end
    
    opts.on("-s", "--screen SCREEN", Integer, "Screen number (default: #{options[:screen]})") do |s|
      options[:screen] = s
    end
    
    opts.on("-d", "--debug", "Enable debug output") do
      options[:debug] = true
    end
    
    opts.on("--dark-mode", "Enable dark mode") do
      options[:dark_mode] = true
    end
    
    opts.on("--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  puts "Starting system tray example (#{options[:width]}x#{options[:height]} on screen #{options[:screen]})"
  puts "Debug output enabled" if options[:debug]
  puts "Dark mode enabled" if options[:dark_mode]
  puts "\nWaiting for systray applications (e.g., nm-applet, volumeicon, etc.)"
  puts "Tip: Run in another terminal: 'nm-applet' or other systray-enabled applications"
  
  # Create system tray with the specified options
  tray = SystemTray.new(options[:width], options[:height], options[:screen], options[:debug], options[:dark_mode])
  
  # Initialize the tray
  if tray.initialize_tray
    puts "System tray initialized successfully"
    
    # Process events
    begin
      tray.process_events
    rescue Interrupt
      puts "\nInterrupted, cleaning up..."
    ensure
      tray.cleanup
    end
  else
    puts "Failed to initialize system tray"
  end
end
