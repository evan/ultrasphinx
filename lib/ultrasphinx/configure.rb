
module Ultrasphinx
  class Configure  
    class << self    
  
      # Force all the indexed models to load and fill the MODEL_CONFIGURATION hash.
      def load_constants
  
        Dir["#{RAILS_ROOT}/app/models/**/*.rb"].each do |filename|
          next if filename =~ /\/(\.svn|CVS|\.bzr)\//
          begin
            open(filename) {|file| load filename if file.grep(/is_indexed/).any?}
          rescue Object => e
            say "warning; possibly critical autoload error on #{filename}"
            say e.inspect
          end
        end 
  
        # Build the field-to-type mappings.
        Fields.instance.configure(MODEL_CONFIGURATION)
      end
                    
      # Main SQL builder.
      def run       
        # XXX break up this method
        load_constants
              
        puts "Rebuilding Ultrasphinx configurations for #{ENV['RAILS_ENV']} environment" 
        puts "Available models are #{MODEL_CONFIGURATION.keys.to_sentence}"
        File.open(CONF_PATH, "w") do |conf|
          conf.puts "\n# Auto-generated at #{Time.now}.\n# Hand modifications will be overwritten.\n"
          
          conf.puts "\n# #{BASE_PATH}"
          conf.puts open(BASE_PATH).read.sub(/^ultrasphinx.*?\{.*?\}/m, '') + "\n"
          
          sphinx_source_list = []
          
          conf.puts "\n# Source configuration\n\n"
  
          puts "Generating SQL"
          MODEL_CONFIGURATION.each_with_index do |model_options, class_id|
            model, options = model_options
            klass, source = model.constantize, model.tableize
  
  #          puts "SQL for #{model}"
            
            sphinx_source_list << source
    
            conf.puts "source #{source}\n{"
            conf.puts SOURCE_DEFAULTS
                      
            # apparently we're supporting postgres now
            connection_settings = klass.connection.instance_variable_get("@config")
  
            adapter_defaults = ADAPTER_DEFAULTS[connection_settings[:adapter]]
            raise ConfigurationError, "Unsupported database adapter" unless adapter_defaults
            conf.puts adapter_defaults
                      
            connection_settings.each do |key, value|
              conf.puts "#{CONFIG_MAP[key]} = #{value}" if CONFIG_MAP[key]          
            end          
            
            table, pkey = klass.table_name, klass.primary_key
            condition_strings, join_strings = Array(options[:conditions]).map{|condition| "(#{condition})"}, []
            column_strings = ["(#{table}.#{pkey} * #{MODEL_CONFIGURATION.size} + #{class_id}) AS id", 
                                         "#{class_id} AS class_id", "'#{klass.name}' AS class"]   
            remaining_columns = Fields.instance.keys - ["class", "class_id"]
            
            conf.puts "\nsql_query_range = SELECT MIN(#{pkey}), MAX(#{pkey}) FROM #{table}"
            
            options[:fields].to_a.each do |f|
              column, as = f.is_a?(Hash) ? [f[:field], f[:as]] : [f, f]
              column_strings << Fields.instance.cast("#{table}.#{column}", as)
              remaining_columns.delete(as)
            end
            
            options[:includes].to_a.each do |join|
              join_klass = join[:model].constantize
              association = klass.reflect_on_association(join[:model].underscore.to_sym)
              if not association 
                if not join[:association_sql]
                  raise ConfigurationError, "Unknown association from #{klass} to #{join[:model]}"
                else
                  join_strings << join[:association_sql]
                end
              else
                join_strings << "LEFT OUTER JOIN #{join_klass.table_name} ON " + 
                  if (macro = association.macro) == :belongs_to 
                    "#{join_klass.table_name}.#{join_klass.primary_key} = #{table}.#{association.primary_key_name}" 
                  elsif macro == :has_one
                    "#{table}.#{klass.primary_key} = #{join_klass.table_name}.#{association.instance_variable_get('@foreign_key_name')}" 
                  else
                    raise ConfigurationError, "Unidentified association macro #{macro.inspect}"
                  end
              end
              column_strings << "#{join_klass.table_name}.#{join[:field]} AS #{join[:as] or join[:field]}"
              remaining_columns.delete(join[:as] || join[:field])
            end
            
            options[:concats].to_a.select{|concat| concat[:model] and concat[:field]}.each do |group|
              # only has_many's or explicit sql right now
              join_klass = group[:model].constantize
              if group[:association_sql]
                join_strings << group[:association_sql]
              else
                association = klass.reflect_on_association(group[:association_name] ? group[:association_name].to_sym :  group[:model].underscore.pluralize.to_sym)
                join_strings << "LEFT OUTER JOIN #{join_klass.table_name} ON #{table}.#{klass.primary_key} = #{join_klass.table_name}.#{association.primary_key_name}" + (" AND (#{group[:conditions]})" if group[:conditions]).to_s # XXX make sure foreign key is right for polymorphic relationships
              end
              column_strings << Fields.instance.cast("GROUP_CONCAT(#{join_klass.table_name}.#{group[:field]} SEPARATOR ' ')", group[:as])
              remaining_columns.delete(group[:as])
            end
            
            options[:concats].to_a.select{|concat| concat[:fields]}.each do |concat|
              column_strings << Fields.instance.cast("CONCAT_WS(' ', #{concat[:fields].map{|field| "#{table}.#{field}"}.join(', ')})", concat[:as])
              remaining_columns.delete(concat[:as])
            end
              
  #          puts "#{model} has #{remaining_columns.inspect} remaining"
            remaining_columns.each do |field|
              column_strings << Fields.instance.null(field)
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
            Fields.instance.each do |field, type|
              case type
                when 'numeric'
                  groups << "sql_group_column = #{field}"
                when 'date'
                  groups << "sql_date_column = #{field}"
              end
            end
            conf.puts "\n" + groups.sort_by{|s| s[/= (.*)/, 1]}.join("\n")
            conf.puts "\nsql_query_info = SELECT * FROM #{table} WHERE #{table}.#{pkey} = (($id - #{class_id}) / #{MODEL_CONFIGURATION.size})"           
            conf.puts "}\n\n"                
          end
          
          conf.puts "\n# Index configuration\n\n"
          
  
          # only output the unified index; no one uses the individual ones anyway        
  
          conf.puts "index #{UNIFIED_INDEX_NAME}"
          conf.puts "{"
          conf.puts sphinx_source_list.map {|s| "source = #{s}" }
  
          OPTIONAL_SPHINX_KEYS.each do |key|
            conf.puts "#{key} = #{PLUGIN_SETTINGS[key]}" if PLUGIN_SETTINGS[key]
          end
          
          conf.puts "path = #{PLUGIN_SETTINGS["path"]}/sphinx_index_#{UNIFIED_INDEX_NAME}"
          conf.puts "}\n\n"
        end
              
      end
      
      def say(s) #:nodoc:
        Ultrasphinx.say s
      end
      
    end 
  end
end
