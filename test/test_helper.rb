
def silently
  old_stdout, $stdout = $stdout, StringIO.new
  yield
  $stdout = old_stdout
end 

RAILS_ROOT = File.dirname(__FILE__)
$LOAD_PATH << "#{RAILS_ROOT}/../lib" << RAILS_ROOT

RAILS_ENV = "test"

require 'rubygems'
require 'initializer'
require 'active_support'
require 'sqlite3'
require 'active_record'
require 'test/spec'
require 'ruby-debug'

ActiveRecord::Base.establish_connection(
  config = {
    :adapter => 'sqlite3',
    :database => ':memory:'
  })
ActiveRecord::Base.connection.instance_variable_set('@config', config)

silently { require 'schema' }
require 'models'
require 'ultrasphinx'

Debugger.start
