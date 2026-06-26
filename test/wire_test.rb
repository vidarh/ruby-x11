# frozen_string_literal: true

require_relative "helper"
require "X11/wire"

# X11::Wire is the shared, direction-agnostic codec (also used by the X12 server).
# These tests prove a single Form definition round-trips BOTH directions and BOTH
# byte orders — the property the client codec lacked (native order, encode-only).
class WireTest < Minitest::Test
  # A representative request shape: opcode, a length field, fields, a value-list.
  class SampleReq < X11::Wire::Form
    field  :opcode, Uint8, value: 12
    field  :detail, Uint8
    length!
    field  :window, Uint32
    field  :value_mask, Uint32
    value_list :values, mask: :value_mask
  end

  def round_trip(order)
    ctx = X11::Wire::Context.new(order)
    bytes = SampleReq.new(detail: 3, window: 0x4001, value_mask: 0b101, values: [0xAA, 0xBB]).encode(ctx)
    # length field (u16 @ offset 2) = total/4
    assert_equal 0, bytes.bytesize % 4, "must be 4-byte aligned"
    assert_equal bytes.bytesize / 4, bytes.byteslice(2, 2).unpack1(ctx.u16)
    back = SampleReq.decode(bytes, ctx)
    assert_equal 12, back.opcode
    assert_equal 3, back.detail
    assert_equal 0x4001, back.window
    assert_equal [0xAA, 0xBB], back.values
  end

  def test_round_trip_lsb = round_trip(:lsb)
  def test_round_trip_msb = round_trip(:msb)

  def test_byte_order_actually_differs
    lsb = SampleReq.new(detail: 0, window: 0x11223344, value_mask: 0, values: []).encode(X11::Wire::Context.lsb)
    msb = SampleReq.new(detail: 0, window: 0x11223344, value_mask: 0, values: []).encode(X11::Wire::Context.msb)
    refute_equal lsb, msb, "LSB and MSB encodings must differ"
    assert_equal "\x44\x33\x22\x11".b, lsb.byteslice(4, 4)
    assert_equal "\x11\x22\x33\x44".b, msb.byteslice(4, 4)
  end

  def test_context_from_setup_byte
    assert_equal :lsb, X11::Wire::Context.from_setup_byte(0x6C).order
    assert_equal :msb, X11::Wire::Context.from_setup_byte("B").order
  end
end
