
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
  
  UNIFIED_INDEX_NAME = "complete"

  COLUMN_TYPES = {:string => 'text', :text => 'text', :integer => 'numeric', :date => 'date', :datetime => 'date' }

  CONFIG_MAP = {:username => 'sql_user',
    :password => 'sql_pass',
    :host => 'sql_host',
    :database => 'sql_db',
    :port => 'sql_port',
    :socket => 'sql_sock'}

  OPTIONAL_SPHINX_KEYS = ['morphology', 'stopwords', 'min_word_len', 'charset_type', 'charset_table', 'docinfo']
  
  # some default settings for the sphinx conf files
  
  SOURCE_DEFAULTS = %(
strip_html = 0
index_html_attrs =
sql_query_post =
sql_range_step = 20000
  )
  
  ADAPTER_DEFAULTS = {
    "mysql" => %(
type = mysql
sql_query_pre = SET SESSION group_concat_max_len = 65535
sql_query_pre = SET NAMES utf8
  ), 
    "postgresql" => %(
type = pgsql
  )}
 
  
  # Configuration file parser.
  def self.options_for(heading, path)
   
    section = open(path).read[/^#{heading}.*?\{(.*?)\}/m, 1]    
    unless section
      Ultrasphinx.say "#{path} appears to be corrupted; please delete it and retry. "
#      raise ConfigurationError, "Missing heading #{heading.inspect}" 
    end
    
    options = section.split("\n").map do |line|
      line =~ /\s*(.*?)\s*=\s*([^\#]*)/
      $1 ? [$1, $2.strip] : []
    end
    
    Hash[*options.flatten] 
  end

  # introspect on the existing generated conf files

  PLUGIN_SETTINGS = options_for('ultrasphinx', BASE_PATH)

  DAEMON_SETTINGS = options_for('searchd', BASE_PATH)

  STOPWORDS_PATH = "#{Ultrasphinx::PLUGIN_SETTINGS['path']}/stopwords.txt"

  MODEL_CONFIGURATION = {}
      
  # Complain if the database names go out of sync.
  def self.verify_database_name
    if File.exist? CONF_PATH
      if options_for("source", CONF_PATH)['sql_db'] != ActiveRecord::Base.connection.instance_variable_get("@config")[:database]
          say "warning; configured database name is out-of-date"
          say "please run 'rake ultrasphinx:configure'"
      end rescue nil
    end
  end
    
  # Logger.
  def self.say msg
    STDERR.puts "** ultrasphinx: #{msg}"
  end
        
end
