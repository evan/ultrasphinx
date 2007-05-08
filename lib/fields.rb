
module Ultrasphinx
  class Fields < Hash
    def initialize
      self["class_id"] = "numeric"
      self["class"] = "text"
    end
  
    def slam(field, new_type)
      field, new_type = field.to_s, COLUMN_TYPES[new_type.to_sym]
      if existing_type = self[field]
        raise ConfigurationError, "Column type mismatch for #{field.inspect}" unless new_type == existing_type
      else
        self[field] = new_type
      end
    end
    
    def cast(source_string, field)
      if self[field] == "date"
        "UNIX_TIMESTAMP(#{source_string})"
      elsif source_string =~ /GROUP_CONCAT/
        "CAST(#{source_string} AS CHAR)"
      else
        source_string              
      end + " AS #{field}"
    end    
      
    def null(field)
      case self[field]
        when 'text'
          "''"
        when 'numeric'
          "0"
        when 'date'
          "UNIX_TIMESTAMP('1970-01-01 00:00:00')"
      end + " AS #{field}"
    end
    
    def configure(configuration)

      configuration.each do |model, options|        
        klass = model.constantize
                
        begin
          # fields are from the model, renames are not allowed right now... use concat (vinegar)
          options[:fields].to_a.each do |field|
            klass.columns_hash[field] and slam(field, klass.columns_hash[field].type) or ActiveRecord::Base.logger.warn "ultrasphinx: WARNING: field #{field} is not present in #{model}"
          end  
          # joins are whatever they are in the target       
          options[:includes].to_a.each do |join|
            slam(join[:as] || join[:field], join[:model].constantize.columns_hash[join[:field]].type)
          end  
          # regular concats are CHAR (I think), group_concats are BLOB and need to be cast to CHAR, e.g. :text
          options[:concats].to_a.each do |concats|
            slam(concats[:as], :text)          
          end          
        rescue ActiveRecord::StatementInvalid
          ActiveRecord::Base.logger.warn "ultrasphinx: WARNING: model #{model} does not exist in the database yet"
        end  
      end
      
      self
    end
    
  end
end
    
