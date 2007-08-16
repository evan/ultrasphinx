
RAILS_ROOT = File.dirname(__FILE__)
$LOAD_PATH << "#{RAILS_ROOT}/../lib" << RAILS_ROOT

RAILS_ENV = "test"

require 'rubygems'
require 'initializer'
require 'active_support'
require 'sqlite3'
require 'active_record'
require 'test/spec'
require 'config/environment'
require 'ultrasphinx'
#require 'stub/client'
