
require 'rubygems'
require 'test/spec'
require 'ruby-debug'

Dir.chdir "#{File.dirname(__FILE__)}/integration/app/" do
  system("rake db:migrate db:fixtures:load us:boot") if ENV['REINDEX']
  require 'config/environment'
end
