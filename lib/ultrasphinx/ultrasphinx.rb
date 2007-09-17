
module Ultrasphinx

  class Exception < ::Exception #:nodoc:
  end
  class ConfigurationError < Exception #:nodoc:
  end  
  class DaemonError < Exception #:nodoc:
  end
  class UsageError < Exception #:nodoc:
  end

  # internal file paths
  
  SUBDIR = "config/ultrasphinx"
  
  DIR = "#{RAILS_ROOT}/#{SUBDIR}"

  CONF_PATH = "#{DIR}/#{RAILS_ENV}.conf"
  
  ENV_BASE_PATH = "#{DIR}/#{RAILS_ENV}.base" 
  
  GENERIC_BASE_PATH = "#{DIR}/default.base"
  
  BASE_PATH = (File.exist?(ENV_BASE_PATH) ? ENV_BASE_PATH : GENERIC_BASE_PATH)
  
  raise ConfigurationError, "Please create a '#{SUBDIR}/#{RAILS_ENV}.base' or '#{SUBDIR}/default.base' file in order to use Ultrasphinx in your #{RAILS_ENV} environment." unless File.exist? BASE_PATH # XXX lame

  # some miscellaneous constants

  MAX_INT = 2**32-1

  MAX_WORDS = 2**16 # maximum number of stopwords built  
  
  EMPTY_SEARCHABLE = "__empty_searchable__"
  
  UNIFIED_INDEX_NAME = "complete"

  CONFIG_MAP = {
    # These must be symbols for key mapping against Rails itself
    :username => 'sql_user',
    :password => 'sql_pass',
    :host => 'sql_host',
    :database => 'sql_db',
    :port => 'sql_port',
    :socket => 'sql_sock'
  }
  
  CONNECTION_DEFAULTS = {
    :host => 'localhost'
  }
  
  ADAPTER_DEFAULTS = {
    'mysql' => %(
type = mysql
sql_query_pre = SET SESSION group_concat_max_len = 65535
sql_query_pre = SET NAMES utf8
  ), 
    'postgresql' => %(
type = pgsql
  )}
     
  # Logger.
  def self.say msg
    STDERR.puts "** ultrasphinx: #{msg}"
  end
  
  # Configuration file parser.
  def self.options_for(heading, path)
    section = open(path).read[/^#{heading}\s*?\{(.*?)\}/m, 1]    
    
    unless section
      Ultrasphinx.say "warning; heading #{heading} not found in #{path}; it may be corrupted. "
      {}
    else      
      options = section.split("\n").map do |line|
        line =~ /\s*(.*?)\s*=\s*([^\#]*)/
        $1 ? [$1, $2.strip] : []
      end      
      Hash[*options.flatten] 
    end
    
  end

  # introspect on the existing generated conf files

  INDEXER_SETTINGS = options_for('indexer', BASE_PATH)
  CLIENT_SETTINGS = options_for('client', BASE_PATH)
  DAEMON_SETTINGS = options_for('searchd', BASE_PATH)
  SOURCE_SETTINGS = options_for('source', BASE_PATH)
  INDEX_SETTINGS = options_for('index', BASE_PATH)

  STOPWORDS_PATH = "#{Ultrasphinx::INDEX_SETTINGS['path']}/stopwords.txt"

  MODEL_CONFIGURATION = {}     

  # Complain if the database names go out of sync.
  def self.verify_database_name
    if File.exist? CONF_PATH
      if options_for(
        "source #{MODEL_CONFIGURATION.keys.first.constantize.table_name}", 
        CONF_PATH
      )['sql_db'] != ActiveRecord::Base.connection.instance_variable_get("@config")[:database]
        say "warning; configured database name is out-of-date"
        say "please run 'rake ultrasphinx:configure'"
      end rescue nil
    end
  end
        
end
