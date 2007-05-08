class BlogPost < ActiveRecord::Base
  is_indexed :fields => ["title", "body", "blog_type", "published_at"],
                   :includes => [{:model => "Category", :field => "name", :as => "category"}],
                   :concats => [{:fields => ["description", "excerpt"], :as => "editorial"},
                                        {:model => "Comment", :field => "body", :as => "comments", 
                                          :conditions => "comments.item_type = '#{base_class}'"}],
                   :conditions => live_condition_string
end

class Ingredient < ActiveRecord::Base
  is_indexed :fields => ["title", "published_at", "body"]
end

class Recipe < ActiveRecord::Base
  is_indexed :fields => ["title", "published_at", "total_time", "active_time"],
                   :concats => [{:fields => ["instructions", "introduction"], :as => "body"},
                                      {:fields => ["long_description", "short_description"], :as => "editorial"},
                                      {:model => "Comment", :field => "body", :as => "comments", 
                                        :conditions => "comments.item_type = '#{base_class}'"}],
#                                      {:model => "Ingredient", :field => "title", :as => "ingredients"}],
                   :conditions => live_condition_string
                   # XXX ingredients
                   # XXX tags                   
end

class Story < ActiveRecord::Base
  is_indexed :fields => ["title", "published_at"],
                  :includes => [{:model => "Category", :field => "name", :as => "category"}],
                  :concats => [{:fields => ["long_description", "short_description"], :as => "editorial"},
                                       {:model => "StoryPage", :field => "body", :as => "body", :association_name => "pages"},
                                       {:model => "Comment", :field => "body", :as => "comments", 
                                         :conditions => "comments.item_type = '#{base_class}'"}],
                  :conditions => live_condition_string
end

class Topic < ActiveRecord::Base
  is_indexed :fields => ["title", "published_at"],
                  :includes => [{:model => "Board", :field => "name", :as => "board"}],
                  :concats => [{:model => "Post", :field => "content", :conditions => "posts.state = 0", :as => "body"},
                                       {:model => "Post", :field => "user_name", :conditions => "posts.state = 0", :as => "user"}],
                  :conditions => "topics.state = 0 OR topics.state = 3"
end

