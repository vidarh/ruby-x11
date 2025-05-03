require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'X11'

# Fix circular dependency by loading minitest after the application code
require 'minitest/spec'
require 'minitest/autorun'
