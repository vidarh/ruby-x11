module X11
  class Screen
    attr_reader :display

    def initialize(display, data)
      @display = display
      @internal = data
    end

    def root        = @internal.root
    def root_depth  = @internal.root_depth
    def root_visual = @internal.root_visual
    def width       = @internal.width_in_pixels
    def height      = @internal.height_in_pixels
    def black_pixel = @internal.black_pixel
    def white_pixel = @internal.white_pixel

    def to_s
      "#<X11::Screen(#{id}) width=#{width} height=#{height}>"
    end
  end
end
