
ActiveRecord::Schema.define(:version => 1) do

  create_table :kennels, :force => true do |t|
    t.column :name, :string
    t.column :created_at, :datetime, :null => false
    t.column :updated_at, :datetime, :null => false
    t.column :residents_count, :integer, :default => 0
  end

  create_table :dogs, :force => true do |t|
    t.column :name, :string
    t.column :created_at, :datetime, :null => false
    t.column :updated_at, :datetime, :null => false
    t.column :kennel_id, :integer, :null => true
  end
  
  create_table :cats, :force => true do |t|
    t.column :name, :string
    t.column :created_at, :datetime, :null => false
    t.column :updated_at, :datetime, :null => false
  end
  
  create_table :cats_kennels, :force => true do |t|
    t.column :kennel_id, :integer, :null => false
    t.column :cat_id, :integer, :null => false  
  end

end
