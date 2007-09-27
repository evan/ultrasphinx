
require "#{File.dirname(__FILE__)}/../test_helper"

describe "a realistic configuration" do

  def _ *args
    Ultrasphinx::Configure.send(args.first, *(args[1..-1]))
  end

  def setup
    @models_configuration = {"Restaurant"=>
  {:conditions=>"restaurants.name NOT LIKE '%duplicate%'",
   :fields=>
    [{:field=>"name", :as=>"title"},
     {:field=>"updated_at", :as=>"published_at"},
     {:field=>"description", :as=>"body"},
     {:field=>"specific_cuisine", :as=>"specific_cuisine"},
     {:field=>"general_cuisine", :facet=>true, :as=>"general_cuisine"},
     {:field=>"neighborhood", :facet=>true, :as=>"neighborhood"}],
   :concatenate=>
    [{:fields=>["general_cuisine", "specific_cuisine"], :as=>"cuisine"},
     {:fields=>
       ["phone",
        "url",
        "location",
        "service",
        "street",
        "city",
        "zip",
        "state",
        "country",
        "atmosphere",
        "hours",
        "place_type"],
      :as=>"hidden"},
     {:class_name=>"Board",
      :field=>"name",
      :association_sql=>
       "LEFT OUTER JOIN restaurants_topics ON restaurants.id = restaurants_topics.restaurant_id LEFT OUTER JOIN topics ON topics.id = restaurants_topics.topic_id LEFT OUTER JOIN boards ON boards.id = topics.board_id",
      :as=>"board"}],
   :include=>
    [{:class_name=>"Board",
      :field=>"id",
      :association_sql=>"",
      :as=>"board_id"}]},
 "BlogPost"=>
  {:conditions=>"blog_posts.state = 50 and blog_posts.published_at <= now()",
   :fields=>
    [{:field=>"title", :as=>"title"},
     {:field=>"body", :as=>"body"},
     {:field=>"blog_type", :as=>"blog_type"},
     {:field=>"published_at", :as=>"published_at"}],
   :concatenate=>
    [{:fields=>["title", "description", "excerpt"], :as=>"editorial"},
     {:class_name=>"Comment",
      :conditions=>"comments.item_type = 'BlogPost'",
      :field=>"body",
      :as=>"comments"}],
   :include=>[{:class_name=>"Category", :field=>"name", :as=>"category"}]},
 "Recipe"=>
  {:conditions=>"recipes.state = 50 and recipes.published_at <= now()",
   :fields=>
    [{:field=>"title", :as=>"title"},
     {:field=>"published_at", :as=>"published_at"},
     {:field=>"total_time", :as=>"total_time"},
     {:field=>"active_time", :as=>"active_time"},
     {:field=>"parent_id", :as=>"recipe_parent_id"}],
   :concatenate=>
    [{:fields=>["instructions", "introduction"], :as=>"body"},
     {:fields=>["title", "long_description", "short_description"],
      :as=>"editorial"},
     {:class_name=>"Comment",
      :conditions=>"comments.item_type = 'Recipe'",
      :field=>"body",
      :as=>"comments"}]},
 "Topic"=>
  {:conditions=>"topics.state = 0 OR topics.state = 3",
   :fields=>
    [{:field=>"title", :as=>"title"},
     {:field=>"post_last_created_at", :as=>"published_at"},
     {:field=>"board_id", :as=>"board_id"}],
   :concatenate=>
    [{:class_name=>"Post",
      :conditions=>"posts.state = 0",
      :field=>"content",
      :as=>"body"},
     {:class_name=>"Post",
      :conditions=>"posts.state = 0",
      :field=>"user_name",
      :as=>"user"}],
   :include=>[{:class_name=>"Board", :field=>"name", :as=>"board"}]},
 "Story"=>
  {:conditions=>"stories.state = 50 and stories.published_at <= now()",
   :fields=>
    [{:field=>"title", :as=>"title"},
     {:field=>"published_at", :as=>"published_at"}],
   :concatenate=>
    [{:fields=>["title", "long_description", "short_description"],
      :as=>"editorial"},
     {:class_name=>"StoryPage",
      "association_name"=>"pages",
      :field=>"body",
      :as=>"body"},
     {:class_name=>"Comment",
      :conditions=>"comments.item_type = 'Story'",
      :field=>"body",
      :as=>"comments"}],
   :include=>[{:class_name=>"Category", :field=>"name", :as=>"category"}]},
 "Ingredient"=>
  {:fields=>
    [{:field=>"title", :as=>"title"},
     {:field=>"published_at", :as=>"published_at"},
     {:field=>"body", :as=>"body"}]}}      
   @sources = @models_configuration.keys.map(&:tableize)
  end
  
  it "should build the unified index" do
    _(:build_index, @sources)[1..-1].join("\n").should.equal(
%[index complete
{
  source = blog_posts
  source = ingredients
  source = recipes
  source = restaurants
  source = stories
  source = topics
  charset_type = utf-8
  charset_table = 0..9, A..Z->a..z, -, _, ., &, a..z,
  min_word_len = 1
  stopwords = 
  path = /opt/local/var/db/sphinx//sphinx_index_complete
  docinfo = extern
  morphology = stem_en
}

])  
  end  
  
  it "should fail for unsupported databases" do        
    should.raise(Ultrasphinx::ConfigurationError) do
      _(:setup_source_database, Dog)
    end
  end

  it "should configure the database for a source" do
    Dog.connection.instance_variable_get('@config').merge!(:adapter => 'mysql')    
    _(:setup_source_database, Dog).should.equal(%[
type = mysql
sql_query_pre = SET SESSION group_concat_max_len = 65535
sql_query_pre = SET NAMES utf8
  
sql_db = :memory:
sql_host = localhost])
  end
  
  it "should setup the global header" do
    _(:global_header)[3..-1].join("\n").should.equal(
%[indexer {
  mem_limit = 256M
}

searchd {
  read_timeout = 5
  max_children = 300
  log = /opt/local/var/db/sphinx/log/searchd.log
  port = 3312
  max_matches = 100000
  query_log = /opt/local/var/db/sphinx/log/query.log
  pid_file = /opt/local/var/db/sphinx/log/searchd.pid
  address = 0.0.0.0
}
])
  end
  
  it "should generate the range select" do
   _(:range_select_string, Dog).should.equal("sql_query_range = SELECT MIN(id), MAX(id) FROM dogs")
  end

  it "should generate the query info select" do
    # This is not very useful since it only affects the command-line client, and can't 
    # retrieve the correct row anyway
   _(:query_info_string, Dog, 1).should.equal("sql_query_info = SELECT * FROM dogs WHERE dogs.id = (($id - 1) / 0)")
  end
  
end
