
require 'rubygems'
require 'test/unit'
require 'ruby-debug'

HERE = File.dirname(__FILE__)
$LOAD_PATH << HERE

require 'integration/app/config/environment'

Dir.chdir "#{HERE}/integration/app" do
  system("rake us:start")
end

def silently
  stderr, $stderr = $stderr, StringIO.new
  yield
  $stderr = stderr
end