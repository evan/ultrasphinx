
require 'singleton'

module Ultrasphinx

  class Fields
    include Singleton
    
    TYPE_MAP = {
      'string' => 'text', 
      'text' => 'text', 
      'integer' => 'numeric', 
      'date' => 'date', 
      'datetime' => 'date'
    }    
    
    attr_accessor :classes, :types
    
    def initialize
      @types = {
        "class_id" => "numeric",
        "class" => "text"
      }
      @classes = Hash.new([])
    end
  
    def save_and_verify_type(field, new_type, klass)
      # tries to smoosh fields together by name in the sphinx query schema; raises if their types don't match
      field, new_type = field.to_s, TYPE_MAP[new_type.to_s]
      if types[field]
        raise ConfigurationError, "Column type mismatch for #{field.inspect}; was already #{types[field].inspect}, but is now #{new_type.inspect}." unless types[field] == new_type
        classes[field] = (classes[field] + [klass]).uniq
      else
        types[field] = new_type
        classes[field] = [klass]
      end
    end
    
    def cast(source_string, field)
      if types[field] == "date"
        "UNIX_TIMESTAMP(#{source_string})"
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
    
    def configure(configuration)

      configuration.each do |model, options|        

        klass = model.constantize        
        classes['class_id'] += [model]
        classes['class'] += [model]
                
        begin
        
          # Fields are from the model. We destructively canonicize them back onto the configuration hash.
          options['fields'] = options['fields'].to_a.map do |entry|
            
            entry = {'field' => entry} unless entry.is_a? Hash
            entry['as'] = entry['field'] unless entry['as']
            
            unless klass.columns_hash[entry['field']]
              ActiveRecord::Base.logger.warn "ultrasphinx: WARNING: field #{entry['field']} is not present in #{model}"
            else
              save_and_verify_type(entry['as'], klass.columns_hash[entry['field']].type, klass)
            end
            
            if entry['facet']
              save_and_verify_type(entry['as'], 'text', klass) # source must be a string
              save_and_verify_type("#{entry['as']}_facet", 'integer', klass)
            end
            
            entry
          end  
          
          # Joins are whatever they are in the target       
          options['include'].to_a.each do |join|
            save_and_verify_type(join['as'] || join['field'], join['class_name'].constantize.columns_hash[join['field']].type, klass)
          end  
          
          # Regular concats are CHAR (I think), group_concats are BLOB and need to be cast to CHAR, e.g. :text
          options['concatenate'].to_a.each do |concats|
            save_and_verify_type(concats['as'], 'text', klass)
          end          
        rescue ActiveRecord::StatementInvalid
          ActiveRecord::Base.logger.warn "ultrasphinx: WARNING: model #{model} does not exist in the database yet"
        end  
      end
      
      self
    end
    
  end
end
    
