# frozen_string_literal: true

# X11::Wire — shared, direction-agnostic X11 wire codec.
#
# This is the codec home for both the pure-x11 client and the X12 server (see the
# X12 repo's docs/codec-foldback-plan.md). It is byte-order-parameterized (via
# Context) and every Form encodes AND decodes, so the same packet definitions work
# from either end. Additive: the legacy X11::Type / X11::Form (client) are
# unchanged and still used by existing dependents.
require_relative "wire/endian"
require_relative "wire/context"
require_relative "wire/type"
require_relative "wire/form"
