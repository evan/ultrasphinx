module Ultrasphinx
  module Associations
  
    def get_association(klass, entry)
      if value = entry['class_name']
        klass.reflect_on_all_associations.detect do |assoc|
          assoc.class_name == value
        end    
      elsif value = entry['association_name']
        klass.reflect_on_all_associations.detect do |assoc|
          assoc.name.to_s == value.to_s
        end 
      end
    end
    
    def get_association_model(klass, entry)
      get_association(klass, entry).class_name.constantize
    end    
    
    def entry_identifies_association?(entry)
      entry['class_name'] || entry['association_name']
    end
    
  end
end