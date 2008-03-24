
# Setup integration system for the integration suite

Dir.chdir "#{File.dirname(__FILE__)}/integration/app/" do

  pid_file = '/tmp/sphinx/searchd.pid'
  if File.exist? pid_file
    pid = File.read(pid_file).to_i
    system("kill #{pid}"); sleep(2); system("kill -9 #{pid}")  
  end
  
  system("rm -rf /tmp/sphinx")  
  system("rm -rf config/ultrasphinx/development.conf")

  Dir.chdir "vendor/plugins" do
    system("rm ultrasphinx")
    system("ln -s ../../../../../ ultrasphinx")
  end
  
  system("rake db:drop")
  system("rake db:create")
  system("rake db:migrate db:fixtures:load")

  system("rake us:boot")
  system("rm /tmp/ultrasphinx-stopwords.txt")
  system("rake ultrasphinx:spelling:build")
end
