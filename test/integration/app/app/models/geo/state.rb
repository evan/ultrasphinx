class Geo::State < ActiveRecord::Base
  has_many :"geo/addresses"
  
  is_indexed :concatenate => [{:class_name => 'Geo::Address', :field => 'name', :as => 'address_name'}]
end
