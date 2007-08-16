
class Kennel < ActiveRecord::Base
  has_many :dogs
  has_many :cats
end

class Dog < ActiveRecord::Base
  belongs_to :kennel
end

class CatsKennel < ActiveRecord::Base
  belongs_to :kennel
  belongs_to :cat  
end

class Cat < ActiveRecord::Base
  has_many :cats_kennels
  has_many :kennels, :through => :cats_kennels
end
