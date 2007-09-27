
require File.join(File.dirname(__FILE__), 'boot')

Rails::Initializer.run do |config|
  if config.action_controller.respond_to? :"session="  
    config.action_controller.session = { :session_key => "_myapp_session", :secret => "this is a super secret phrase" }
  end
end
