
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'X11'

display = X11::Display.new

display.client_message(
  mask: X11::Form::SubstructureNotifyMask | X11::Form::SubstructureRedirectMask,
  type: :_NET_CURRENT_DESKTOP,
  data: ARGV.shift.to_i
)

