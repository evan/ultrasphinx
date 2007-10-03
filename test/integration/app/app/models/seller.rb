class Seller < ActiveRecord::Base
  belongs_to :user  
  delegate :address, :to => :user
  
  is_indexed :fields => ['company_name', 'created_at', 'capitalization', 'user_id']  
end
