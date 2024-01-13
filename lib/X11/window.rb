
module X11

  # A simple helper class that makes requests where the
  # target object is a specific window a bit more convenient
  class Window
    attr_reader :dpy, :wid

    def initialize(dpy,wid)
      @dpy, @wid = dpy,wid
    end

    def self.create(dpy, ...)
      wid = dpy.create_window(...)
      Window.new(dpy,wid)
    end
    
    def query_tree                 = dpy.query_tree(@wid)
    def map                        = dpy.map_window(@wid)
    def unmap                      = dpy.unmap_window(@wid)
    def destroy                    = dpy.destroy_window(@wid)
    def get_geometry               = dpy.get_geometry(@wid)
    def configure(...)             = dpy.configure_window(@wid, ...)
    def get_property(...)          = dpy.get_property(@wid,...)
    def grab_key(arg, ...)         = dpy.grab_key(arg, @wid, ...)
    def grab_button(arg,...)       = dpy.grab_button(arg, @wid, ...)
    def change_property(mode, ...) = dpy.change_property(mode, @wid, ...)
    def set_input_focus(mode)      = dpy.set_input_focus(mode, @wid)
    def select_input(...)          = dpy.select_input(@wid,...)
    def get_window_attributes(...) = dpy.get_window_attributes(@wid,...)
    def change_attributes(...)     = dpy.change_window_attributes(@wid,...)

    def image_text16(...) = dpy.image_text16(@wid, ...)
    def clear_area(arg, ...) = dpy.clear_area(arg, @wid, ...)
    def poly_fill_rectangle(...) = dpy.poly_fill_rectangle(@wid, ...)
    def put_image(type, ...) = dpy.put_image(type, @wid, ...)
    def create_gc(...) = dpy.create_gc(@wid, ...)
  end
end
