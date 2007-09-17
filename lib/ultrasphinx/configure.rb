
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

        load_constants
              
        puts "Rebuilding Ultrasphinx configurations for #{ENV['RAILS_ENV']} environment" 
        puts "Available models are #{MODEL_CONFIGURATION.keys.to_sentence}"
        File.open(CONF_PATH, "w") do |conf|
        
          conf.puts global_header            
          sources = []
          
          puts "Generating SQL"
          cached_groups = Fields.instance.groups.join("\n")
          MODEL_CONFIGURATION.each_with_index do |model_options, class_id|
            model, options = model_options
            klass, source = model.constantize, model.tableize    
            sources << source              
            conf.puts build_source(model, options, class_id, klass, source, cached_groups)
          end
          
          conf.puts build_index(sources)
        end              
      end
      
      
      ######
      
      private
      
      def global_header
        ["\n# Auto-generated at #{Time.now}.",
         "# Hand modifications will be overwritten.",
         "# #{BASE_PATH}",
         INDEXER_SETTINGS._to_conf_string('indexer'),
         DAEMON_SETTINGS._to_conf_string("searchd")]
      end      
      
      
      def setup_source_database(klass)
        # Tentatively supporting Postgres now
        connection_settings = klass.connection.instance_variable_get("@config")

        adapter_defaults = ADAPTER_DEFAULTS[connection_settings[:adapter]]
        raise ConfigurationError, "Unsupported database adapter" unless adapter_defaults

        conf = [adapter_defaults]                  
        connection_settings.reverse_merge(CONNECTION_DEFAULTS).each do |key, value|
          conf << "#{CONFIG_MAP[key]} = #{value}" if CONFIG_MAP[key]          
        end                 
        conf.join("\n")
      end
      
      
      def setup_source_arrays(klass, class_id, conditions)        
        condition_strings = Array(conditions).map do |condition| 
          "(#{condition})"
        end
        
        table, pkey = klass.table_name, klass.primary_key
        column_strings = [
          "(#{table}.#{pkey} * #{MODEL_CONFIGURATION.size} + #{class_id}) AS id", 
          "#{class_id} AS class_id", "'#{klass.name}' AS class", 
          "'#{EMPTY_SEARCHABLE}' AS empty_searchable"]
        remaining_columns = Fields.instance.types.keys - ["class", "class_id", "empty_searchable"]        
        [column_strings, [], condition_strings, remaining_columns]
      end
      
      
      def range_select_string(klass)
        table, pkey = klass.table_name, klass.primary_key
        "\nsql_query_range = SELECT MIN(#{pkey}), MAX(#{pkey}) FROM #{table}"
      end
      
      
      def query_info_string(klass, class_id)
        table, pkey = klass.table_name, klass.primary_key
        "\nsql_query_info = SELECT * FROM #{table} WHERE #{table}.#{pkey} = (($id - #{class_id}) / #{MODEL_CONFIGURATION.size})"
      end      
      
            
      def build_source(model, options, class_id, klass, source, groups)
                
        column_strings, join_strings, condition_strings, remaining_columns = 
          setup_source_arrays(klass, class_id, options[:conditions])

        column_strings, join_strings, remaining_columns = 
          build_regular_fields(klass, options['fields'], column_strings, join_strings, remaining_columns)
        column_strings, join_strings, remaining_columns = 
          build_includes(klass, options['include'], column_strings, join_strings, remaining_columns)
        column_strings, join_strings, remaining_columns = 
          build_concatenations(klass, options['concatenate'], column_strings, join_strings, remaining_columns)
        
        column_strings = add_missing_columns(remaining_columns, column_strings)
       
        ["\n# Source configuration\n\n",
         "source #{source}\n{",
          SOURCE_SETTINGS._to_conf_string,
          setup_source_database(klass),
          range_select_string(klass),
          build_query(klass, column_strings, join_strings, condition_strings),
          "\n" + groups,
          query_info_string(klass, class_id),
          "}\n\n"]
      end
      
      
      def build_query(klass, column_strings, join_strings, condition_strings)

        connection_settings = klass.connection.instance_variable_get("@config")
        table, pkey = klass.table_name, klass.primary_key

        ["sql_query =", 
          "SELECT", 
          column_strings.sort_by do |string| 
            # sphinx wants them always in the same order, but "id" must be first
            (field = string[/.*AS (.*)/, 1]) == "id" ? "*" : field
          end.join(", "),
          "FROM #{klass.table_name}",
          join_strings.uniq,
          "WHERE #{table}.#{pkey} >= $start AND #{table}.#{pkey} <= $end",
          condition_strings.uniq.map do |condition| 
            "AND #{condition}"
          end,
          ("GROUP BY id" if connection_settings[:adapter] == 'mysql') # XXX should be somewhere more obvious
        ].flatten.join(" ")
      end
      
      
      def add_missing_columns(remaining_columns, column_strings)
        remaining_columns.each do |field|
          column_strings << Fields.instance.null(field)
        end
        column_strings
      end
      

      def build_regular_fields(klass, entries, column_strings, join_strings, remaining_columns)          
        entries.to_a.each do |entry|
          source_string = "#{klass.table_name}.#{entry['field']}"
          column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)
        end
        
        [column_strings, join_strings, remaining_columns]
      end
      

      def build_includes(klass, entries, column_strings, join_strings, remaining_columns)                  
        entries.to_a.each do |entry|
          
          join_klass = entry['class_name'].constantize
          association = klass.reflect_on_association(entry['class_name'].underscore.to_sym)
                        
          raise ConfigurationError, "Unknown association from #{klass} to #{entry['class_name']}" if not association and not entry['association_sql']
          
          join_strings = install_join_unless_association_sql(entry['association_sql'], nil, join_strings) do 
            "LEFT OUTER JOIN #{join_klass.table_name} ON " + 
            if (macro = association.macro) == :belongs_to 
              "#{join_klass.table_name}.#{join_klass.primary_key} = #{klass.table_name}.#{association.primary_key_name}" 
            elsif macro == :has_one
              "#{klass.table_name}.#{klass.primary_key} = #{join_klass.table_name}.#{association.instance_variable_get('@foreign_key_name')}" 
            else
              raise ConfigurationError, "Unidentified association macro #{macro.inspect}"
            end
          end
          
          source_string = "#{join_klass.table_name}.#{entry['field']}"
          column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)                         
        end
        
        [column_strings, join_strings, remaining_columns]
      end
      
        
      def build_concatenations(klass, entries, column_strings, join_strings, remaining_columns)
        entries.to_a.each do |entry|
          if entry['class_name'] and entry['field']
            # group concats
            # only has_many's or explicit sql right now
            join_klass = entry['class_name'].constantize
        
            join_strings = install_join_unless_association_sql(entry['association_sql'], nil, join_strings) do 
              # XXX make sure foreign key is right for polymorphic relationships
              association = klass.reflect_on_association(entry['association_name'] ? entry['association_name'].to_sym : entry['class_name'].underscore.pluralize.to_sym)
              "LEFT OUTER JOIN #{join_klass.table_name} ON #{klass.table_name}.#{klass.primary_key} = #{join_klass.table_name}.#{association.primary_key_name}" + 
                (entry['conditions'] ? " AND (#{entry['conditions']})" : "")
            end
            
            source_string = "GROUP_CONCAT(#{join_klass.table_name}.#{entry['field']} SEPARATOR ' ')"
            column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)
            
          elsif entry['fields']
            # regular concats
            source_string = "CONCAT_WS(' ', " + entry['fields'].map do |subfield| 
              "#{klass.table_name}.#{subfield}"
            end.join(', ') + ")"
            
            column_strings, remaining_columns = install_field(source_string, entry['as'], entry['function_sql'], entry['facet'], column_strings, remaining_columns)              

          else
            raise ConfigurationError, "Invalid concatenate parameters for #{model}: #{entry.inspect}."
          end
        end
        
        [column_strings, join_strings, remaining_columns]
      end
      
    
      def build_index(sources)
        ["\n# Index configuration\n\n",
          "index #{UNIFIED_INDEX_NAME}\n{",
          sources.map do |source| 
            "source = #{source}"
          end.join("\n"),          
          INDEX_SETTINGS.merge('path' => INDEX_SETTINGS['path'] + "/sphinx_index_#{UNIFIED_INDEX_NAME}")._to_conf_string,
         "}\n\n"]
      end
      
    
      def install_field(source_string, as, function_sql, with_facet, column_strings, remaining_columns)
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
      
      
      def install_join_unless_association_sql(association_sql, join_string, join_strings)
        join_strings << (association_sql or join_string or yield)
      end
      
      
      def say(s)
        Ultrasphinx.say s
      end
      
    end 
  end
end
