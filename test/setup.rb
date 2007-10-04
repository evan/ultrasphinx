
# Setup integration system for the integration suite

Dir.chdir "#{File.dirname(__FILE__)}/integration/app/" do
  system("rake db:create db:migrate db:fixtures:load")
  system("rake us:boot")
  system("sudo rake ultrasphinx:spelling:build")
end
