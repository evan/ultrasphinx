
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
          conf.puts "\n# Auto-generated at #{Time.now}.\n# Hand modifications will be overwritten.\n# #{BASE_PATH}"          
          
          conf.puts INDEXER_SETTINGS._to_conf_string("indexer")
          conf.puts DAEMON_SETTINGS._to_conf_string("searchd")
          
          sphinx_source_list = []
          
          conf.puts "\n# Source configuration\n\n"
  
          puts "Generating SQL"
          MODEL_CONFIGURATION.each_with_index do |model_options, class_id|
            model, options = model_options
            klass, source = model.constantize, model.tableize
  
  #          puts "SQL for #{model}"
            
            sphinx_source_list << source
    
            conf.puts "source #{source}\n{"
            conf.puts SOURCE_SETTINGS._to_conf_string
                      
            # Tentatively supporting Postgres now
            connection_settings = klass.connection.instance_variable_get("@config")
  
            adapter_defaults = ADAPTER_DEFAULTS[connection_settings[:adapter]]
            raise ConfigurationError, "Unsupported database adapter" unless adapter_defaults
            conf.puts adapter_defaults
                      
            connection_settings.reverse_merge(CONNECTION_DEFAULTS).each do |key, value|
              conf.puts "#{CONFIG_MAP[key]} = #{value}" if CONFIG_MAP[key]          
            end          
            
            table, pkey = klass.table_name, klass.primary_key
            condition_strings, join_strings = Array(options[:conditions]).map{|condition| "(#{condition})"}, []
            column_strings = ["(#{table}.#{pkey} * #{MODEL_CONFIGURATION.size} + #{class_id}) AS id", 
                                         "#{class_id} AS class_id", "'#{klass.name}' AS class", 
                                         "'#{EMPTY_SEARCHABLE}' AS empty_searchable"
                                      ]
            remaining_columns = Fields.instance.types.keys - ["class", "class_id", "empty_searchable"]
            
            conf.puts "\nsql_query_range = SELECT MIN(#{pkey}), MAX(#{pkey}) FROM #{table}"
            
            # regular fields
            options['fields'].to_a.each do |entry|
              source_string = "#{table}.#{entry['field']}"
              column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)
            end
            
            # includes
            options['include'].to_a.each do |entry|
              
              join_klass = entry['class_name'].constantize
              association = klass.reflect_on_association(entry['class_name'].underscore.to_sym)
                            
              raise ConfigurationError, "Unknown association from #{klass} to #{entry['class_name']}" if not association and not entry['association_sql']
              
              join_strings = install_join_unless_association_sql(entry['association_sql'], nil, join_strings) do 
                "LEFT OUTER JOIN #{join_klass.table_name} ON " + 
                if (macro = association.macro) == :belongs_to 
                  "#{join_klass.table_name}.#{join_klass.primary_key} = #{table}.#{association.primary_key_name}" 
                elsif macro == :has_one
                  "#{table}.#{klass.primary_key} = #{join_klass.table_name}.#{association.instance_variable_get('@foreign_key_name')}" 
                else
                  raise ConfigurationError, "Unidentified association macro #{macro.inspect}"
                end
              end
              
              source_string = "#{join_klass.table_name}.#{entry['field']}"
              column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)              
            end
            
            # group concats
            options['concatenate'].to_a.each do |entry|
              if entry['class_name'] and entry['field']
                # only has_many's or explicit sql right now
                join_klass = entry['class_name'].constantize
  
                join_strings = install_join_unless_association_sql(entry['association_sql'], nil, join_strings) do 
                  # XXX make sure foreign key is right for polymorphic relationships
                  association = klass.reflect_on_association(entry['association_name'] ? entry['association_name'].to_sym : entry['class_name'].underscore.pluralize.to_sym)
                  "LEFT OUTER JOIN #{join_klass.table_name} ON #{table}.#{klass.primary_key} = #{join_klass.table_name}.#{association.primary_key_name}" + 
                    (entry['conditions'] ? " AND (#{entry['conditions']})" : "")
                end
                
                source_string = "GROUP_CONCAT(#{join_klass.table_name}.#{entry['field']} SEPARATOR ' ')"
                column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)
              elsif entry['fields']
                # regular concats
                source_string = "CONCAT_WS(' ', " + entry['fields'].map do |subfield| 
                  "#{table}.#{subfield}"
                end.join(', ') + ")"
                
                column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)              
              else
                raise ConfigurationError, "Invalid concatenate parameters for #{model}: #{entry.inspect}."
              end
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
            
            # XXX should be configured somewhere more obvious
            query_strings << "GROUP BY id" if connection_settings[:adapter] == 'mysql'
            
            conf.puts "sql_query = #{query_strings.join(" ")}"
            
            groups = []
            # group and date sorting params... this really only would have to be run once
            Fields.instance.types.each do |field, type|
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
          sphinx_source_list.each do |source| 
            conf.puts "source = #{source}"
          end
          
          conf.puts INDEX_SETTINGS.merge(
            'path' => INDEX_SETTINGS['path'] + "/sphinx_index_#{UNIFIED_INDEX_NAME}"
          )._to_conf_string
  
          conf.puts "}\n\n"
        end
              
      end
      
      def install_field(source_string, as, function_sql, with_facet, column_strings, remaining_columns) #:nodoc:
        source_string = function_sql.sub('?', source_string) if function_sql

        column_strings << Fields.instance.cast(source_string, as)
        remaining_columns.delete(as)
        
        # Generate CRC integer fields for text grouping
        if with_facet
          # Postgres probably doesn't handle this
          column_strings << "CRC32(#{source_string}) AS #{as}_facet"
          remaining_columns.delete("#{as}_facet")
        end
        [column_strings, remaining_columns]
      end
      
      def install_join_unless_association_sql(association_sql, join_string, join_strings) #:nodoc:
        join_strings << (association_sql or join_string or yield)
      end
      
      def say(s) #:nodoc:
        Ultrasphinx.say s
      end
      
    end 
  end
end
