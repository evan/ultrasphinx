
# Setup integration system for the integration suite

puts ["Please make sure that test/integration/app/vendor/rails is symlinked",
  "to a Rails trunk checkout in order for the rake tasks to run properly."]

Dir.chdir "#{File.dirname(__FILE__)}/integration/app/" do
  system("rm -rf /tmp/sphinx")
  Dir.chdir "vendor/plugins" do
    system("rm ultrasphinx; ln -s ../../../../../ ultrasphinx")
  end
  system("rake db:create")
  system("rake db:migrate db:fixtures:load")
  system("rake us:boot")
  system("sudo rake ultrasphinx:spelling:build")
end
