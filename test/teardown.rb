
# Tear down integration system for the integration suite

Dir.chdir "#{File.dirname(__FILE__)}/integration/app/" do  
  # Remove the symlink created by the setup method, for people with tools
  # that can't handle recursive directories (Textmate).
  system("rm vendor/plugins/ultrasphinx") unless ENV['USER'] == 'eweaver'
end