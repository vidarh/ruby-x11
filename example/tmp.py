# Panel Systray Implementation for X11
# Pseudocode covering the main elements of systray implementation

class SystemTray:
    def __init__(self, panel, screen_number=0):
        self.panel = panel
        self.screen_number = screen_number
        self.embedded_icons = {}  # Map of window IDs to icon objects
        self.tray_atom = None
        self.display = None
        self.tray_window = None
        self.initialized = False
        
    def initialize(self):
        # Connect to X display
        self.display = XOpenDisplay(None)
        if not self.display:
            print("Failed to open X display")
            return False
            
        # Create the tray window
        self.tray_window = XCreateSimpleWindow(
            self.display,
            XDefaultRootWindow(self.display),
            0, 0,  # position
            1, 1,  # size (will be resized later)
            0,     # border width
            0,     # border color
            0      # background color
        )
        
        # Get all the X atoms we'll need
        self.atoms = {
            "MANAGER": XInternAtom(self.display, "MANAGER", False),
            "SYSTEM_TRAY_REQUEST_DOCK": XInternAtom(self.display, "_NET_SYSTEM_TRAY_OPCODE", False),
            "SYSTEM_TRAY_BEGIN_MESSAGE": XInternAtom(self.display, "_NET_SYSTEM_TRAY_MESSAGE_DATA", False),
            "SYSTEM_TRAY_ORIENTATION": XInternAtom(self.display, "_NET_SYSTEM_TRAY_ORIENTATION", False),
            "XEMBED_INFO": XInternAtom(self.display, "_XEMBED_INFO", False),
            "XEMBED": XInternAtom(self.display, "_XEMBED", False),
        }
        
        # Create the selection atom name (screen specific)
        selection_atom_name = f"_NET_SYSTEM_TRAY_S{self.screen_number}"
        self.tray_atom = XInternAtom(self.display, selection_atom_name, False)
        
        # Try to get ownership of the system tray selection
        timestamp = XGetCurrentTime(self.display)
        result = XSetSelectionOwner(self.display, self.tray_atom, self.tray_window, timestamp)
        
        if result == 0:
            print("Could not acquire system tray selection - another panel might be running")
            return False
            
        # Check if we really got the selection
        owner = XGetSelectionOwner(self.display, self.tray_atom)
        if owner != self.tray_window:
            print("Failed to get system tray selection owner")
            return False
            
        # Announce that we're the system tray manager by sending a MANAGER client message
        self._send_manager_notification(timestamp)
        
        # Set up event mask for our tray window
        XSelectInput(self.display, self.tray_window, 
                    StructureNotifyMask | SubstructureNotifyMask | SubstructureRedirectMask)
        
        # Set properties on our tray window
        self._set_tray_orientation(SYSTEM_TRAY_ORIENTATION_HORZ)  # Default to horizontal
        
        # Set up event handling for client messages
        self.panel.add_event_handler(ClientMessage, self._handle_client_message)
        
        self.initialized = True
        return True
        
    def _send_manager_notification(self, timestamp):
        # Send MANAGER client message to the root window to announce our presence
        root = XDefaultRootWindow(self.display)
        
        event = XClientMessageEvent()
        event.type = ClientMessage
        event.window = root
        event.message_type = self.atoms["MANAGER"]
        event.format = 32
        event.data.l[0] = timestamp
        event.data.l[1] = self.tray_atom
        event.data.l[2] = self.tray_window
        
        XSendEvent(self.display, root, False, StructureNotifyMask, &event)
        XFlush(self.display)
        
    def _set_tray_orientation(self, orientation):
        # Set the orientation property on our tray window
        # orientation: SYSTEM_TRAY_ORIENTATION_HORZ or SYSTEM_TRAY_ORIENTATION_VERT
        data = [orientation]
        XChangeProperty(
            self.display, 
            self.tray_window,
            self.atoms["SYSTEM_TRAY_ORIENTATION"],
            XA_CARDINAL, 
            32,
            PropModeReplace,
            &data, 
            1
        )
        
    def _handle_client_message(self, event):
        # Handle client messages sent to our tray window
        if event.message_type == self.atoms["SYSTEM_TRAY_REQUEST_DOCK"]:
            if event.format == 32:
                # Extract the window ID of the application requesting to be docked
                icon_window = event.data.l[1]
                self._dock_icon(icon_window)
                
    def _dock_icon(self, icon_window):
        if icon_window in self.embedded_icons:
            print(f"Window {icon_window} already docked")
            return
            
        # Check if the window exists
        window_attributes = XWindowAttributes()
        status = XGetWindowAttributes(self.display, icon_window, &window_attributes)
        if status == 0:
            print(f"Window {icon_window} does not exist")
            return
            
        # Add event mask to the icon window
        XSelectInput(self.display, icon_window, 
                    StructureNotifyMask | PropertyChangeMask)
                
        # Reparent the icon window to our tray window (this is the actual embedding)
        XReparentWindow(
            self.display,
            icon_window,
            self.tray_window,
            0, 0  # position - will be adjusted in _layout_icons()
        )
        
        # Create an icon object to track this window
        icon = {
            "window": icon_window,
            "width": ICON_DEFAULT_SIZE,
            "height": ICON_DEFAULT_SIZE,
            "visible": False
        }
        
        # Request the XEMBED_INFO property if available
        self._get_xembed_info(icon)
        
        # Store the icon in our tracking map
        self.embedded_icons[icon_window] = icon
        
        # Send XEMBED message to tell the icon it's embedded
        self._send_xembed_message(
            icon_window,
            XEMBED_EMBEDDED_NOTIFY,
            0,  # detail
            self.tray_window,  # embed_info_window
            XEMBED_VERSION
        )
        
        # Make it visible if needed
        if window_attributes.map_state == IsViewable:
            XMapRaised(self.display, icon_window)
            icon["visible"] = True
            
        # Adjust layout 
        self._layout_icons()
        
    def _get_xembed_info(self, icon):
        # Get XEMBED_INFO property from the icon window
        actual_type = Atom()
        actual_format = c_int()
        nitems = c_ulong()
        bytes_after = c_ulong()
        data = POINTER(c_ulong)()
        
        status = XGetWindowProperty(
            self.display,
            icon["window"],
            self.atoms["XEMBED_INFO"],
            0, 2,  # offset, length
            False,  # delete
            self.atoms["XEMBED_INFO"],
            &actual_type, &actual_format,
            &nitems, &bytes_after, &data
        )
        
        if status == Success and data:
            # Extract XEMBED_INFO flags
            if nitems >= 2:
                flags = data[1]
                icon["xembed_flags"] = flags
                
                # Check if the icon wants to be mapped
                if flags & XEMBED_MAPPED:
                    XMapRaised(self.display, icon["window"])
                    icon["visible"] = True
            
            XFree(data)
            
    def _send_xembed_message(self, window, message, detail, data1, data2):
        # Send an XEMBED client message to a specific window
        event = XClientMessageEvent()
        event.type = ClientMessage
        event.window = window
        event.message_type = self.atoms["XEMBED"]
        event.format = 32
        event.data.l[0] = XGetCurrentTime(self.display)
        event.data.l[1] = message
        event.data.l[2] = detail
        event.data.l[3] = data1
        event.data.l[4] = data2
        
        XSendEvent(self.display, window, False, NoEventMask, &event)
        XFlush(self.display)
        
    def _layout_icons(self):
        # Calculate the layout of icons in the tray
        # This is called when icons are added/removed or the panel size changes
        
        # Get current size of panel's tray area
        tray_width = self.panel.get_tray_width()
        tray_height = self.panel.get_tray_height()
        
        XResizeWindow(self.display, self.tray_window, tray_width, tray_height)
        
        # Layout logic depends on orientation
        orientation = self.panel.get_orientation()
        spacing = 2  # pixels between icons
        
        if orientation == SYSTEM_TRAY_ORIENTATION_HORZ:
            # Horizontal layout
            x = 0
            for window_id, icon in self.embedded_icons.items():
                if not icon["visible"]:
                    continue
                    
                # Move and resize the icon window
                XMoveResizeWindow(
                    self.display,
                    icon["window"],
                    x, 0,  # position
                    icon["width"], icon["height"]  # size
                )
                
                x += icon["width"] + spacing
        else:
            # Vertical layout
            y = 0
            for window_id, icon in self.embedded_icons.items():
                if not icon["visible"]:
                    continue
                    
                # Move and resize the icon window
                XMoveResizeWindow(
                    self.display,
                    icon["window"],
                    0, y,  # position
                    icon["width"], icon["height"]  # size
                )
                
                y += icon["height"] + spacing
                
        XFlush(self.display)
        
    def handle_icon_destroyed(self, window):
        # Called when an icon window is destroyed
        if window in self.embedded_icons:
            del self.embedded_icons[window]
            self._layout_icons()
            
    def handle_icon_configure(self, window, width, height):
        # Called when an icon window changes size
        if window in self.embedded_icons:
            self.embedded_icons[window]["width"] = width
            self.embedded_icons[window]["height"] = height
            self._layout_icons()
            
    def handle_icon_map(self, window):
        # Called when an icon window is mapped (made visible)
        if window in self.embedded_icons:
            self.embedded_icons[window]["visible"] = True
            self._layout_icons()
            
    def handle_icon_unmap(self, window):
        # Called when an icon window is unmapped (hidden)
        if window in self.embedded_icons:
            self.embedded_icons[window]["visible"] = False
            self._layout_icons()
            
    def cleanup(self):
        # Release the selection ownership
        if self.initialized and self.display:
            XSetSelectionOwner(self.display, self.tray_atom, None, XGetCurrentTime(self.display))
            
            # Destroy tray window
            XDestroyWindow(self.display, self.tray_window)
            
            # Close display
            XCloseDisplay(self.display)
