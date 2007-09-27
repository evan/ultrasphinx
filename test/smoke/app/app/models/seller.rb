class Seller < ActiveRecord::Base
  # Sphinx
  is_indexed :fields => ['company_name', 'created_at']
  
  belongs_to :user
  
  delegate :address,    :to => :user
end
