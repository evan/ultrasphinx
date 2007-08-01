
require "#{File.dirname(__FILE__)}/../vendor/sphinx/lib/client"

require 'ultrasphinx/core_extensions'
require 'ultrasphinx/ultrasphinx'
require 'ultrasphinx/autoload'
require 'ultrasphinx/fields'
require 'ultrasphinx/is_indexed'
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

