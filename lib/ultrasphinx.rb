
require 'fileutils'
require 'chronic'
require 'singleton'

require "#{File.dirname(__FILE__)}/../vendor/sphinx/lib/client"

require 'ultrasphinx/ultrasphinx'
require 'ultrasphinx/core_extensions'
require 'ultrasphinx/configure'
require 'ultrasphinx/autoload'
require 'ultrasphinx/fields'
require 'ultrasphinx/is_indexed'
require 'ultrasphinx/search/internals'
require 'ultrasphinx/search/parser'
require 'ultrasphinx/search'

Ultrasphinx.say(
  begin
    require 'raspell'
    require 'ultrasphinx/spell'
    "spelling support enabled"
  rescue Object => e
    "spelling support not available (module load raised \"#{e}\")"
  end
)

if defined? RAILS_ENV and RAILS_ENV == "development"
  if ENV['USER'] == 'eweaver'
    require 'ruby-debug'
    Debugger.start
  end
end