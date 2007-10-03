
require 'rubygems'
require 'test/unit'
require 'ruby-debug'

$LOAD_PATH << File.dirname(__FILE__)

require 'integration/app/config/environment'

def silently
  stderr, $stderr = $stderr, StringIO.new
  yield
  $stderr = stderr
end