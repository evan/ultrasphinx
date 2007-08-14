
ENV['RAILS_ENV'] ||= "development"

namespace :ultrasphinx do  
  
  desc "Bootstrap a full Sphinx environment"
  task :bootstrap => [:environment, :configure, :index, :start] do
  end
  
  desc "Rebuild the configuration file for this particular environment."
  task :configure => :environment do
    Ultrasphinx::Configure.run
  end
  
  desc "Reindex the database and send an update signal to the search daemon."
  task :index => :environment do
    cmd = "indexer --config #{Ultrasphinx::CONF_PATH}"
    cmd << " #{ENV['OPTS']} " if ENV['OPTS']
    cmd << " --rotate" if ultrasphinx_daemon_running?
    cmd << " #{Ultrasphinx::UNIFIED_INDEX_NAME}"
    puts cmd
    system cmd
  end
  
  
  namespace :daemon do
    desc "Start the search daemon"
    task :start => :environment do
      raise Ultrasphinx::DaemonError, "Already running" if ultrasphinx_daemon_running?
      # remove lockfiles
      Dir[Ultrasphinx::PLUGIN_SETTINGS["path"] + "*spl"].each {|file| File.delete(file)}
      system "searchd --config #{Ultrasphinx::CONF_PATH}"
      sleep(2) # give daemon a chance to write the pid file
      if ultrasphinx_daemon_running?
        puts "Started successfully"
      else
        puts "Failed to start"
      end
    end
    
    desc "Stop the search daemon"
    task :stop => [:environment] do
      raise Ultrasphinx::DaemonError, "Doesn't seem to be running" unless ultrasphinx_daemon_running?
      system "kill #{pid = ultrasphinx_daemon_pid}"
      puts "Stopped #{pid}."
    end

    desc "Restart the search daemon"
    task :restart => [:environment, :stop, :start] do
    end
    
    desc "Check if the search daemon is running"
    task :status => :environment do
      if ultrasphinx_daemon_running?
        puts "Daemon is running."
      else
        puts "Daemon is stopped."
      end
    end      
  end
          
    
  namespace :spelling do
    desc "Rebuild custom spelling dictionary"
    task :build => :environment do    
      ENV['OPTS'] = "--buildstops #{Ultrasphinx::STOPWORDS_PATH} #{Ultrasphinx::MAX_WORDS} --buildfreqs"
      Rake::Task["ultrasphinx:index"].invoke
      tmpfile = "/tmp/custom_words.txt"
      words = []
      puts "Filtering"
      File.open(Ultrasphinx::STOPWORDS_PATH).each do |line|
        if line =~ /^([^\s\d_]{4,}) (\d+)/
          # XXX should be configurable
          words << $1 if $2.to_i > 40 
          # ideally we would also skip words within X edit distance of a correction
          # by aspell-en, in order to not add typos to the dictionary
        end
      end
      puts "Writing #{words.size} words"
      File.open(tmpfile, 'w').write(words.join("\n"))
      puts "Loading into aspell"
      system("aspell --lang=en create master custom.rws < #{tmpfile}")
    end
  end
  
end

# task shortcuts
namespace :us do
  task :start => ["ultrasphinx:daemon:start"]
  task :restart => ["ultrasphinx:daemon:restart"]
  task :stop => ["ultrasphinx:daemon:stop"]
  task :stat => ["ultrasphinx:daemon:status"]
  task :in => ["ultrasphinx:index"]
  task :spell => ["ultrasphinx:spelling:build"]
  task :conf => ["ultrasphinx:configure"]  
  task :boot => ["ultrasphinx:bootstrap"]  
end

# support methods

def ultrasphinx_daemon_pid
  open(open(Ultrasphinx::BASE_PATH).readlines.map do |line| 
    line[/^\s*pid_file\s*=\s*([^\s\#]*)/, 1]
  end.compact.first).readline.chomp rescue nil # XXX ridiculous
end

def ultrasphinx_daemon_running?
  ultrasphinx_daemon_pid and `ps #{ultrasphinx_daemon_pid} | wc`.to_i > 1 
end
