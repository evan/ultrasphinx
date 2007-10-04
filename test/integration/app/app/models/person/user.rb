class User < ActiveRecord::Base
  has_one   :seller
  has_one   :address, :class_name => "Geo::Address"

  is_indexed :fields => ['login', 'email', 'deleted'], 
    :include => [{:class_name => 'Seller', :field => 'company_name', :as => 'company'}],
    :conditions => 'deleted = 0'  
  
end
