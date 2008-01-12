
require 'rubygems'
require 'test/unit'
require 'ruby-debug'
require 'multi_rails_init'

HERE = File.dirname(__FILE__)
$LOAD_PATH << HERE

require 'integration/app/config/environment'

Dir.chdir "#{HERE}/integration/app" do
  system("rake us:start")
end
