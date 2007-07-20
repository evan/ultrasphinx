
require 'ultrasphinx/core_extensions'
require 'ultrasphinx/ultrasphinx'
require 'ultrasphinx/autoload'
require 'ultrasphinx/fields'
require 'ultrasphinx/is_indexed'
require 'ultrasphinx/search'

$stderr.puts(
begin
  require 'raspell'
  require 'ultrasphinx/spell'
  "** ultrasphinx: spelling support enabled"
rescue Object => e
  "** ultrasphinx: spelling support not available (module load raised \"#{e}\")"
end)

