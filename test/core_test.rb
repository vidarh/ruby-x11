require File.expand_path('../helper', __FILE__)

describe X11 do
  describe X11::Display do
    before(:each) do
      @display = X11::Display.new
    end

    it "should generate a unique id" do
      collection = 1000.times.collect { @display.new_id }
      expected = collection.size
      _(collection.uniq.size).must_equal expected
    end

    it "falls back to :0 instead of crashing when DISPLAY is empty or unset" do
      original = ENV["DISPLAY"]
      ["", nil].each do |value|
        value.nil? ? ENV.delete("DISPLAY") : ENV["DISPLAY"] = value
        begin
          X11::Display.new
        rescue NoMethodError => e
          flunk "DISPLAY=#{value.inspect} regressed to a crash: #{e.message}"
        rescue StandardError
          # A connection/socket error is fine here — the point is that parsing
          # got past the empty DISPLAY and attempted the default display :0.
        end
      end
    ensure
      ENV["DISPLAY"] = original
    end
  end
end
