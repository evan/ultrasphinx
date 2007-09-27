
require File.join(File.dirname(__FILE__), 'boot')

Rails::Initializer.run do |config|
    config.action_controller.session = { :session_key => "_myapp_session", :secret => "this is a super secret phrase" }
end

# Dependencies.log_activity = true
