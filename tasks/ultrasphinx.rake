
ENV['RAILS_ENV'] ||= "development"

namespace :ultrasphinx do  
  desc "Rebuild the configuration file for this particular environment."
  task :configure => :environment do
    Ultrasphinx::configure
  end
  
  desc "Reindex the database and send an update signal to the search daemon."
  task :index => :environment do
    cmd = "indexer --config #{Ultrasphinx::CONF_PATH}"
    cmd << " #{ENV['OPTS']} " if ENV['OPTS']
    cmd << " --rotate" if daemon_running?
    cmd << " complete"
    puts cmd
    exec cmd
  end
  
  namespace :daemon do
    desc "Start the search daemon"
    task :start => :environment do
      raise Ultrasphinx::DaemonError, "Already running" if daemon_running?
      # remove lockfiles
      Dir[Ultrasphinx::PLUGIN_SETTINGS["path"] + "*spl"].each {|file| File.delete(file)}
      exec "searchd --config #{Ultrasphinx::CONF_PATH}"
    end
    
    desc "Stop the search daemon"
    task :stop => [:environment] do
      raise Ultrasphinx::DaemonError, "Doesn't seem to be running" unless daemon_running?
      system "kill #{daemon_pid}"
    end

    desc "Restart the search daemon"
    task :restart => [:environment, :stop, :start] do
    end
    
    desc "Tail queries in the log"
    task :tail => :environment do
      require 'file/tail'
      puts "Tailing #{filename = Ultrasphinx::DAEMON_SETTINGS['query_log']}"
      File.open(filename) do |log|
        log.extend(File::Tail)
        log.interval = 1
        log.backward(10)
        last = nil
        log.tail do |line| 
          current = line[/\[\*\](.*)$/, 1]
          last = current and puts current unless current == last
        end
      end 
    end
    
    desc "Check if the search daemon is running"
    task :status => :environment do
      if daemon_running?
        puts "Running."
      else
        puts "Stopped."
      end
    end      
  end
    
  namespace :spelling do
    desc "Rebuild custom spelling dictionary"
    task :build => :environment do    
      system "rake ultrasphinx:index OPTS='--buildstops #{Ultrasphinx::STOPWORDS_PATH} #{Ultrasphinx::MAX_WORDS} --buildfreqs'"
      tmpfile = "/tmp/custom_words.txt"
      words = []
      puts "Filtering"
      File.open(Ultrasphinx::STOPWORDS_PATH).each do |line|
        if line =~ /^([^\s\d_]{4,}) (\d+)/
          words << $1 if $2.to_i > 40 # XXX should be configurable
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

def daemon_pid
  open(open(Ultrasphinx::BASE_PATH).readlines.map do |line| 
    line[/^\s*pid_file\s*=\s*([^\s\#]*)/, 1]
  end.compact.first).readline.chomp rescue nil # XXX ridiculous
end

def daemon_running?
  daemon_pid and `ps #{daemon_pid} | wc`.to_i > 1 
end


