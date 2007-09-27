
module Ultrasphinx

=begin rdoc
This is a special singleton configuration class that stores the index field configurations. Rather than using a magic hash and including relevant behavior in Ultrasphinx::Configure and Ultrasphinx::Search, we unify it here.
=end

  class Fields
    include Singleton
    
    TYPE_MAP = {
      'string' => 'text', 
      'text' => 'text', 
      'integer' => 'numeric', 
      'date' => 'date', 
      'datetime' => 'date',
      'timestamp' => 'date',
      'float' => 'numeric'
    }
    
    VERSIONS_REQUIRED = {'float' => '0.9.9'}
    
    attr_accessor :classes, :types
    
    def initialize
      @types = {}
      @classes = Hash.new([])
      @groups = []
    end
    
    def groups
      @groups.compact.sort_by do |string| 
        string[/= (.*)/, 1]
      end
    end
  
    def save_and_verify_type(field, new_type, string_sortable, klass)
      # Smoosh fields together based on their name in the Sphinx query schema
      check_version(new_type.to_s)
      field, new_type = field.to_s, TYPE_MAP[new_type.to_s]

      if types[field]
        # Existing field name; verify its type
        raise ConfigurationError, "Column type mismatch for #{field.inspect}; was already #{types[field].inspect}, but is now #{new_type.inspect}." unless types[field] == new_type
        classes[field] = (classes[field] + [klass]).uniq

      else
        # New field      
        types[field] = new_type
        classes[field] = [klass]

        @groups << case new_type
          when 'numeric'
            "sql_group_column = #{field}"
          when 'date'
            "sql_date_column = #{field}"
          when 'text' 
            "sql_str2ordinal_column = #{field}" if string_sortable
        end
      end
    end
    
    def cast(source_string, field)
      if types[field] == "date"
        "#{ADAPTER_SQL_FUNCTIONS[ADAPTER]['timestamp']}#{source_string})"
      elsif source_string =~ /GROUP_CONCAT/
        "CAST(#{source_string} AS CHAR)"
      else
        source_string              
      end + " AS #{field}"
    end    
      
    def null(field)      
      case types[field]
        when 'text'
          "''"
        when 'numeric'
          "0"
        when 'date'
          "UNIX_TIMESTAMP('1970-01-01 00:00:00')"
        else
          raise "Field #{field} does not have a valid type."
      end + " AS #{field}"
    end
    
    def check_version(field)
      # XXX Awkward location for the compatibility check
      if VERSIONS_REQUIRED[field]
        req = VERSIONS_REQUIRED.delete(field)
        unless SPHINX_VERSION.include? req
          # Will we eventually need to check version ranges?
          Ultrasphinx.say "warning: '#{field}' type requires Sphinx #{req}, but you have #{SPHINX_VERSION}"
        end
      end
    end
    
    def configure(configuration)

      configuration.each do |model, options|        

        klass = model.constantize        
        save_and_verify_type('class_id', 'integer', nil, klass)
        save_and_verify_type('class', 'string', nil, klass)
                
        begin
        
          # Fields are from the model. We destructively canonicize them back onto the configuration hash.
          options['fields'] = options['fields'].to_a.map do |entry|
            
            entry = {'field' => entry} unless entry.is_a? Hash
            entry['as'] = entry['field'] unless entry['as']
            
            unless klass.columns_hash[entry['field']]
              Ultrasphinx.say "warning: field #{entry['field']} is not present in #{model}"
            else
              save_and_verify_type(entry['as'], klass.columns_hash[entry['field']].type, entry['sortable'], klass)
            end
            
            if entry['facet']
              save_and_verify_type(entry['as'], 'text', nil, klass) # source must be a string
              save_and_verify_type("#{entry['as']}_facet", 'integer', nil, klass)
            end
            
            entry
          end  
          
          # Joins are whatever they are in the target       
          options['include'].to_a.each do |entry|
            save_and_verify_type(entry['as'] || entry['field'], entry['class_name'].constantize.columns_hash[entry['field']].type, entry['sortable'], klass)
          end  
          
          # Regular concats are CHAR (I think), group_concats are BLOB and need to be cast to CHAR, e.g. :text
          options['concatenate'].to_a.each do |entry|
            save_and_verify_type(entry['as'], 'text', entry['sortable'], klass)
          end          
        rescue ActiveRecord::StatementInvalid
          Ultrasphinx.say "warning: model #{model} does not exist in the database yet"
        end  
      end
      
      self
    end
    
  end
end
    
