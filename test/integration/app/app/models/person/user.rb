class User < ActiveRecord::Base
  has_one   :seller
  has_one   :address, :class_name => "Geo::Address"

  is_indexed :fields => ['login', 'email', 'deleted'], 
    :include => [{:class_name => 'Seller', :field => 'company_name', :as => 'company'},
      {:class_name => 'Seller', :field => 'sellers_two.company_name', :as => 'company_two', 'association_sql' => 'LEFT OUTER JOIN sellers AS sellers_two ON users.id = sellers.user_id', 'function_sql' => "REPLACE(?, 'seller', '')"}],
    :conditions => 'deleted = 0'  
  
end
