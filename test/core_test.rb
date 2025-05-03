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
  end
end
