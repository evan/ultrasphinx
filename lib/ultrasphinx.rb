
require 'yaml'

module Ultrasphinx

  class Exception < ::Exception
  end
  class ConfigurationError < Exception
  end  
  class DaemonError < Exception
  end

  SPHINX_CONF = "#{RAILS_ROOT}/config/environments/sphinx.#{RAILS_ENV}.conf"
  ENV_BASE = "#{RAILS_ROOT}/config/environments/sphinx.#{RAILS_ENV}.base" 
  GENERIC_BASE = "#{RAILS_ROOT}/config/sphinx.base"
  BASE = (File.exist?(ENV_BASE) ? ENV_BASE : GENERIC_BASE)
  
  raise ConfigurationError, "Please create a #{BASE} configuration file." unless File.exist? BASE
  
  class << self
    def options_for(heading)
      Hash[*(open(BASE).read[/^#{heading}.*?\{(.*?)\}/m, 1].split("\n").reject{|l| l.strip.empty?}.map{|c| c =~ /\s*(.*?)\s*=\s*([^\#]*)/; $1 ? [$1, $2.strip] : []}.flatten)] 
    end
  end
  
  SOURCE_DEFAULTS = "strip_html = 0\nindex_html_attrs =\nsql_query_pre = SET SESSION group_concat_max_len = 65535\nsql_query_post =\nsql_range_step = 20000"
  MAX_INT = 2**32-1
  COLUMN_TYPES = {:string => 'text', :text => 'text', :integer => 'numeric', :date => 'date', :datetime => 'date' }
  CONFIG_MAP = {:username => 'sql_user',
    :password => 'sql_pass',
    :host => 'sql_host',
    :database => 'sql_db',
    :adapter => 'type',
    :port => 'sql_port',
    :socket => 'sql_sock'}
  OPTIONAL_SPHINX_KEYS = ['morphology', 'stopwords', 'min_word_len', 'charset_type', 'charset_table', 'docinfo']
  PLUGIN_CONF = options_for('ultrasphinx')
  DAEMON_CONF = options_for('searchd')
  #logger.debug "Ultrasphinx options are: #{PLUGIN_CONF.inspect}"

  MODELS_CONF = {}
  FIELDS = Fields.new    
    
  class << self    
    def load_constants
      Dir["#{RAILS_ROOT}/app/models/**/*.rb"].each do |filename|
        next if filename =~ /svn|CVS|bzr/
        begin
          open(filename) {|file| load filename if file.grep(/is_indexed/).any?}
        rescue Object => e
          puts "Ultrasphinx: warning; autoload error on #{filename}"
        end
      end 
      FIELDS.configure(MODELS_CONF)
    end
  
    def index *opts
      cmd = "indexer --config #{SPHINX_CONF}"
      opts.each do |opt|
        cmd << " --#{opt}"
      end
      cmd << " --rotate" if daemon_running?
      cmd << " complete"
      puts cmd
      exec cmd      
    end
    
    def daemon(action = :start)
      case action
        when :start
          raise DaemonError, "Already running" if daemon_running?
          # remove lockfiles
          Dir[PLUGIN_CONF["path"] + "*spl"].each {|file| File.delete(file)}
          exec "searchd --config #{SPHINX_CONF}"
        when :stop
          raise DaemonError, "Doesn't seem to be running" unless daemon_running?
          exec "kill #{get_daemon_pid}"
      end
    end
   
    def get_daemon_pid
      # really need a generic way to query the conf file
      open(open(BASE).readlines.map{|s| s[/^\s*pid_file\s*=\s*([^\s\#]*)/, 1]}.compact.first).readline.chomp rescue nil
    end    
    
    def daemon_running?     
      if get_daemon_pid
        `ps #{get_daemon_pid} | wc`.to_i > 1 
      else
        false
      end
    end
   
    def configure       
      load_constants
            
      puts "Rebuilding Ultrasphinx configurations for #{ENV['RAILS_ENV']} environment" 
      puts "Available models are #{MODELS_CONF.keys.to_sentence}"
      File.open(SPHINX_CONF, "w") do |conf|
        conf.puts "\n# Auto-generated at #{Time.now}.\n# Hand modifications will be overwritten.\n"
        
        conf.puts "\n# #{BASE}"
        conf.puts open(BASE).read.sub(/^ultrasphinx.*?\{.*?\}/m, '') + "\n"
        
        index_list = {"complete" => []}
        
        conf.puts "\n# Source configuration\n\n"

        puts "Generating SQL"
        MODELS_CONF.each_with_index do |model_options, class_id|
          model, options = model_options
          klass, source = model.constantize, model.tableize

#          puts "SQL for #{model}"
          
          index_list[source] = [source]
          index_list["complete"] << source
  
          conf.puts "source #{source}\n{"
          conf.puts SOURCE_DEFAULTS        
          klass.connection.instance_variable_get("@config").each do |key, value|
            conf.puts "#{CONFIG_MAP[key]} = #{value}" if CONFIG_MAP[key]          
          end
          
          table, pkey = klass.table_name, klass.primary_key
          condition_strings, join_strings = Array(options[:conditions]).map{|condition| "(#{condition})"}, []
          column_strings = ["(#{table}.#{pkey} * #{MODELS_CONF.size} + #{class_id}) AS id", 
                                       "#{class_id} AS class_id", "'#{klass.name}' AS class"]   
          remaining_columns = FIELDS.keys - ["class", "class_id"]
          
          conf.puts "\nsql_query_range = SELECT MIN(#{pkey}), MAX(#{pkey}) FROM #{table}"
          
          options[:fields].to_a.each do |f|
            column, as = f.is_a?(Hash) ? [f[:field], f[:as]] : [f, f]
            column_strings << FIELDS.cast("#{table}.#{column}", as)
            remaining_columns.delete(as)
          end
          
          options[:includes].to_a.each do |join|
            join_klass = join[:model].constantize
            association = klass.reflect_on_association(join[:model].underscore.to_sym)
            join_strings << "LEFT OUTER JOIN #{join_klass.table_name} ON " + 
              if (macro = association.macro) == :belongs_to 
                "#{join_klass.table_name}.#{join_klass.primary_key} = #{table}.#{association.primary_key_name}" 
              elsif macro == :has_one
                "#{table}.#{klass.primary_key} = #{join_klass.table_name}.#{association.instance_variable_get('@foreign_key_name')}" 
              else
                raise ConfigurationError, "Unidentified association macro #{macro.inspect}"
              end
            column_strings << "#{join_klass.table_name}.#{join[:field]} AS #{join[:as] or join[:field]}"
            remaining_columns.delete(join[:as] || join[:field])
          end
          
          options[:concats].to_a.select{|concat| concat[:model] and concat[:field]}.each do |group|
            # only has_many's right now
            join_klass = group[:model].constantize
            association = klass.reflect_on_association(group[:association_name] ? group[:association_name].to_sym :  group[:model].underscore.pluralize.to_sym)
            join_strings << "LEFT OUTER JOIN #{join_klass.table_name} ON #{table}.#{klass.primary_key} = #{join_klass.table_name}.#{association.primary_key_name}" + (" AND (#{group[:conditions]})" if group[:conditions]).to_s # XXX make sure foreign key is right for polymorphic relationships
            column_strings << FIELDS.cast("GROUP_CONCAT(#{join_klass.table_name}.#{group[:field]} SEPARATOR ' ')", group[:as])
            remaining_columns.delete(group[:as])
          end
          
          options[:concats].to_a.select{|concat| concat[:fields]}.each do |concat|
            column_strings << FIELDS.cast("CONCAT_WS(' ', #{concat[:fields].map{|field| "#{table}.#{field}"}.join(', ')})", concat[:as])
            remaining_columns.delete(concat[:as])
          end
            
#          puts "#{model} has #{remaining_columns.inspect} remaining"
          remaining_columns.each do |field|
            column_strings << FIELDS.null(field)
          end
          
          query_strings = ["SELECT", column_strings.sort_by do |string| 
            # sphinx wants them always in the same order, but "id" must be first
            (field = string[/.*AS (.*)/, 1]) == "id" ? "*" : field
          end.join(", ")] 
          query_strings << "FROM #{table}"                      
          query_strings += join_strings.uniq
          query_strings << "WHERE #{table}.#{pkey} >= $start AND #{table}.#{pkey} <= $end"
          query_strings += condition_strings.uniq.map{|s| "AND #{s}"}
          query_strings << "GROUP BY id"
          
          conf.puts "sql_query = #{query_strings.join(" ")}"
          
          groups = []
          # group and date sorting params... this really only would have to be run once
          FIELDS.each do |field, type|
            case type
              when 'numeric'
                groups << "sql_group_column = #{field}"
              when 'date'
                groups << "sql_date_column = #{field}"
            end
          end
          conf.puts "\n" + groups.sort_by{|s| s[/= (.*)/, 1]}.join("\n")
          conf.puts "\nsql_query_info = SELECT * FROM #{table} WHERE #{table}.#{pkey} = (($id - #{class_id}) / #{MODELS_CONF.size})"           
          conf.puts "}\n\n"                
        end
        
        conf.puts "\n# Index configuration\n\n"
        index_list.to_a.sort_by {|x| x.first == "complete" ? 1 : 0}.each do |name, source_list|
          conf.puts "index #{name}\n{"
          source_list.each {|source| conf.puts "source = #{source}"}
          OPTIONAL_SPHINX_KEYS.each do |key|
            conf.puts "#{key} = #{PLUGIN_CONF[key]}" if PLUGIN_CONF[key]
          end
          conf.puts "path = #{PLUGIN_CONF["path"]}/sphinx_index_#{name}"
          conf.puts "}\n\n"        
        end
      end
            
    end
        
  end
end
