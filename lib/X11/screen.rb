module X11
  class Screen
    attr_reader :display

    def initialize(display, data)
      @display = display
      @internal = data
    end

    def root
      @internal.root
    end

    def root_depth
      @internal.root_depth
    end

    def root_visual
      @internal.root_visual
    end

    def width
      @internal.width_in_pixels
    end

    def height
      @internal.height_in_pixels
    end

    def to_s
      "#<X11::Screen(#{id}) width=#{width} height=#{height}>"
    end
  end
end
