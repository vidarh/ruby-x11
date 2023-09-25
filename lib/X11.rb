module X11
  class X11Error < StandardError; end
end

require 'socket'
require_relative './X11/protocol'
require_relative './X11/auth'
require_relative './X11/display'
require_relative './X11/screen'
require_relative './X11/type'
require_relative './X11/form'
require_relative './X11/keysyms'
