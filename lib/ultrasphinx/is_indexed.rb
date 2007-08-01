
require 'ultrasphinx'

module ActiveRecord
  class Base

=begin rdoc

The is_indexed macro configures a model for indexing. Its parameters are used to generate SQL queries for Sphinx.

== Indexing single fields

Use the <tt>:fields</tt> key.

Accepts an array of field names. 
  :fields => ["created_at", "title", "body"]

== Indexing fields from belongs_to associations

Use the <tt>:includes</tt> key.

Accepts an array of hashes. 

Each should contain a <tt>:model</tt> key (the class name of the included model), a <tt>:field</tt> key (the name of the field to include), and an optional <tt>:as</tt> key (what to name the field in the parent). You can use the optional key <tt>:association_sql</tt> if you need to pass a custom JOIN string, in which case the default JOIN will not be generated.

== Scoping the searchable records

Use the <tt>:conditions</tt> key.

SQL conditions, to scope which records are selected for indexing. Accepts a string. 
  :conditions => "created_at < NOW() AND deleted IS NOT NULL"
The <tt>:conditions</tt> key is especially useful if you delete records by marking them deleted rather than removing them from the database.

== Concatenating multiple fields

Use the <tt>:concats</tt> key (MySQL only).

Accepts an array of option hashes, which can be of two types: 

1. To concatenate many fields within one record, use a regular (or horizontal) concatenation. Regular concatenations contain a <tt>:fields</tt> key (again, an array of field names), and a mandatory <tt>:as</tt> key (the name of the result of the concatenation). For example, to concatenate the <tt>title</tt> and <tt>body</tt> into one field called <tt>text</tt>: 
  :concats => [{:fields => ["title", "body"], :as => "text"}]

2. To group and concatenate a field from a set of associated records, use a group (or vertical) concatenation. Group concatenations join into another table, and can be used to index a number of associated models as one field in a parent model. Group concatenations contain a <tt>:model</tt> key (the class name of the included model), a <tt>:field</tt> key (the field on the included model to concatenate), and an optional <tt>:as</tt> key (also the name of the result of the concatenation). For example, to concatenate all <tt>Post#body</tt> contents into the parent's <tt>responses</tt> field:
  :concats => {:model => "Post", :field => "body", :as => "responses"}

Optional group concatenation keys are <tt>:association_name</tt> (if your <tt>has_many</tt> association can't be derived from the model name), <tt>:association_sql</tt>, if you need to pass a custom JOIN string (for example, a double JOIN for a <tt>has_many :through</tt>), and <tt>:conditions</tt> (if you need custom WHERE conditions for this particular association).

== Example

Here's an example configuration using most of the options, taken from production code:

  class Story < ActiveRecord::Base  
    is_indexed :fields => [
        "title", 
        "published_at"
      ],
      :includes => [
        {:model => "Category", :field => "name", :as => "category"}
      ],      
      :concats => [
        {:fields => ["title", "long_description", "short_description"], :as => "editorial"},
        {:model => "Page", :field => "body", :as => "body", :association_name => "pages"},
        {:model => "Comment", :field => "body", :as => "comments", 
          :conditions => "comments.item_type = '#{base_class}'"}
      ],
      :conditions => self.live_condition_string
  end  

=end
  
    def self.is_indexed opts = {}
    
      opts.assert_valid_keys [:fields, :concats, :conditions, :includes, :nulls]
      
      Array(opts[:concats]).each do |concat|
        concat.assert_valid_keys [:model, :conditions, :field, :as, :fields, :association_name, :association_sql]
        raise Ultrasphinx::ConfigurationError, "You can't mix regular concat and group concats" if concat[:fields] and (concat[:field] or concat[:model] or concat[:association_name])
        raise Ultrasphinx::ConfigurationError, "Group concats must not have multiple fields" if concat[:field].is_a? Array
        raise Ultrasphinx::ConfigurationError, "Regular concats should have multiple fields" if concat[:fields] and !concat[:fields].is_a?(Array)
      end
      
      Array(opts[:joins]).each do |join|
        join.assert_valid_keys [:model, :field, :as]
      end
      
      Ultrasphinx::MODEL_CONFIGURATION[self.name] = opts
    end
  end
end
