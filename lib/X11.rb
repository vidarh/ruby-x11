module X11
  class X11Error < StandardError; end
end

require 'socket'
require 'active_support'
require 'hexdump'
require 'X11/protocol'
require 'X11/auth'
require 'X11/display'
require 'X11/screen'
require 'X11/type'
require 'X11/form'
