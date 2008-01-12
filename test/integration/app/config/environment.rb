
RAILS_GEM_VERSION = ENV['MULTIRAILS_RAILS_VERSION'] if ENV['MULTIRAILS_RAILS_VERSION']

require File.join(File.dirname(__FILE__), 'boot')
require 'action_controller'

Rails::Initializer.run do |config|
  config.action_controller.session = { :session_key => "_myapp_session", :secret => "7c74979e7db2230f84adbb4b3eb77d05" }
  config.load_paths << "#{RAILS_ROOT}/app/models/person" # moduleless model path
end

# Dependencies.log_activity = true
