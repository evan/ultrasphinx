
$LOAD_PATH << "#{File.dirname(__FILE__)}/../lib"
RAILS_ROOT = File.dirname(__FILE__)
RAILS_ENV = "test"

require 'rubygems'
require 'initializer'
require 'active_support'
require 'test/spec'
require 'ultrasphinx'

