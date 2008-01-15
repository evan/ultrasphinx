
require 'rubygems'
require 'test/unit'
require 'echoe'
require 'multi_rails_init'

if defined? ENV['MULTIRAILS_RAILS_VERSION']
  ENV['RAILS_GEM_VERSION'] = ENV['MULTIRAILS_RAILS_VERSION']
end

Echoe.silence do
  HERE = File.expand_path(File.dirname(__FILE__))
  $LOAD_PATH << HERE
  LOG = "#{HERE}/integration/app/log/development.log"     
end

require 'integration/app/config/environment'

Dir.chdir "#{HERE}/integration/app" do
  system("rake us:start")
end
