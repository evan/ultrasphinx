ENV['RAILS_ENV'] ||= "development"

namespace :ultrasphinx do  
  desc "Rebuild the configuration file for this particular environment."
  task :configure => :environment do
    Ultrasphinx::configure
  end
  
  desc "Reindex the actual data and send an update signal to the search daemon."
  task :index => :environment do
    Ultrasphinx::index
  end
  
  task :index_with_word_frequencies => :environment do
    Ultrasphinx::index("buildstops #{Ultrasphinx::PLUGIN_CONF['path']}/stopwords.txt #{2**16}", "buildfreqs")
  end
  
  namespace :daemon do
    desc "Start the search daemon"
    task :start => :environment do
      Ultrasphinx::daemon(:start)
    end
    
    desc "Stop the search daemon"
    task :stop => :environment do
      Ultrasphinx::daemon(:stop)
    end

    desc "Restart the search daemon"
    task :restart => :environment do
      Ultrasphinx::daemon(:stop)
      Ultrasphinx::daemon(:start)
    end
    
    desc "Check if the search daemon is running"
    task :status => :environment do
      if Ultrasphinx::daemon_running?
        puts "Running as pid #{Ultrasphinx::get_daemon_pid}"
      else
        puts "Not running"
      end
    end      
  end
    
  namespace :spelling do
    desc "(re)build custom chow spelling dictionary"
    task :build => :environment do    
      system("rake ultrasphinx:index_with_word_frequencies")
      tmpfile = "/tmp/custom_words.txt"
      words = []
      puts "Filtering"
      File.open("#{Ultrasphinx::PLUGIN_CONF['path']}/stopwords.txt").each do |line|
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
#      File.delete(tmpfile)
    end
  end
  
end

