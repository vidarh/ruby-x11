require File.expand_path('../helper', __FILE__)

class MockSocket
  def initialize(packet)
    @packet = packet
  end

  def read(amount)
    @packet.slice!(0..amount-1)
  end
end

class Point < X11::Form::BaseForm
  field :x, Int8
  field :y, Int8
end

class Child < X11::Form::BaseForm
  field :name, Uint16, :length
  field :name, String8, :string
end

class Parent < X11::Form::BaseForm
  field :value, Uint8
  field :point, Point

  field :name, Uint16, :length
  field :name, String8, :string

  field :children, Uint16, :length
  field :children, Child, :list
end

describe X11::Form::BaseForm do
  it "setters and getters on form should work" do

    # we can create partial form objects
    # without specifying all parameters.
    parent = Parent.new(1337)

    # To fill in the rest of the parameters
    # we use attr_accessors
    parent.name = "Parent Form"
    parent.point = Point.new(0,0)

    _(parent.point).must_be_instance_of Point
    _(parent.name).must_equal "Parent Form"

    parent.children = []
    parent.children << Child.new
    parent.children << Child.new

    assert_equal parent.children.size, 2
  end

  it "should encode/decode a packet" do
    parent = Parent.new(255,Point.new(23,17), "Parent Form", [])
    socket = MockSocket.new(parent.to_packet)

    decoded = Parent.from_packet(socket)
    _(decoded.value).must_equal 255
    _(decoded.name).must_equal "Parent Form"
    _(decoded.point.x).must_equal 23
    _(decoded.point.y).must_equal 17
  end
end
