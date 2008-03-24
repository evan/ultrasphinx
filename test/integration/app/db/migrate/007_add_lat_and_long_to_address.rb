class AddLatAndLongToAddress < ActiveRecord::Migration
  def self.up
    add_column :addresses, :lat, :double
    add_column :addresses, :lng, :double
  end

  def self.down
    remove_column :addresses, :lat
    remove_column :addresses, :lng
  end
end
