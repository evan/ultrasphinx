
require 'fileutils'
require 'chronic'
require 'singleton'

if defined? RAILS_ENV and RAILS_ENV == "development"
  if ENV['USER'] == 'eweaver'
    require 'ruby-debug'
    Debugger.start
  end
end

$LOAD_PATH << "#{File.dirname(__FILE__)}/../vendor/riddle/lib"
require 'riddle'

require 'ultrasphinx/ultrasphinx'
require 'ultrasphinx/core_extensions'
require 'ultrasphinx/is_indexed'

if (ActiveRecord::Base.connection rescue nil)
  require 'ultrasphinx/configure'
  require 'ultrasphinx/autoload'
  require 'ultrasphinx/fields'

  require 'ultrasphinx/search/internals'
  require 'ultrasphinx/search/parser'
  require 'ultrasphinx/search'

  begin
    require 'raspell'
  rescue Object => e
  end
  
  require 'ultrasphinx/spell'
end

