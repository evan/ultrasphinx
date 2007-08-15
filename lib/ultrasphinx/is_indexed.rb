
require 'ultrasphinx'

module ActiveRecord
  class Base

=begin rdoc

The is_indexed method configures a model for indexing. Its parameters help generate SQL queries for Sphinx.

= Options

== Including regular fields

Use the <tt>:fields</tt> key.

Accepts an array of field names. 
  :fields => ["created_at", "title", "body"]

== Including a field from an association

Use the <tt>:includes</tt> key.

Accepts an array of hashes. 

Each should contain a <tt>:model</tt> key (the class name of the included model), a <tt>:field</tt> key (the name of the field to include), and an optional <tt>:as</tt> key (what to name the field in the parent). You can use the optional key <tt>:association_sql</tt> if you need to pass a custom JOIN string, in which case the default JOIN for <tt>belongs_to</tt> will not be generated.

== Requiring conditions

Use the <tt>:conditions</tt> key.

SQL conditions, to scope which records are selected for indexing. Accepts a string. 
  :conditions => "created_at < NOW() AND deleted IS NOT NULL"
The <tt>:conditions</tt> key is especially useful if you delete records by marking them deleted rather than removing them from the database.

== Concatenating several fields within a record

Use the <tt>:concats</tt> key (MySQL only).

Accepts an array of option hashes. 

To concatenate several fields within one record as a combined field, use a regular (or horizontal) concatenation. Regular concatenations contain a <tt>:fields</tt> key (again, an array of field names), and a mandatory <tt>:as</tt> key (the name of the result of the concatenation). For example, to concatenate the <tt>title</tt> and <tt>body</tt> into one field called <tt>text</tt>: 
  :concats => [{:fields => ["title", "body"], :as => "text"}]

== Concatenating one field from a set of associated records 

Also use the <tt>:concats</tt> key.

To concatenate one field from a set of associated records as a combined field in the parent record, use a group (or vertical) concatenation. A group concatenation should contain a <tt>:model</tt> key (the class name of the included model), a <tt>:field</tt> key (the field on the included model to concatenate), and an optional <tt>:as</tt> key (also the name of the result of the concatenation). For example, to concatenate all <tt>Post#body</tt> contents into the parent's <tt>responses</tt> field:
  :concats => [{:model => "Post", :field => "body", :as => "responses"}]

Optional group concatenation keys are <tt>:association_name</tt> (if your <tt>has_many</tt> association can't be derived from the model name), <tt>:association_sql</tt>, if you need to pass a custom JOIN string (for example, a double JOIN for a <tt>has_many :through</tt>), and <tt>:conditions</tt> (if you need custom WHERE conditions for this particular association).

Ultrasphinx is not an object-relational mapper, and the association generation is intended to stay minimal--don't be afraid of <tt>:association_sql</tt>.

= Examples

== Complex configuration

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
        {:fields => ["title", "long_description", "short_description"], 
          :as => "editorial"},
        {:model => "Page", :field => "body", :as => "body", 
          :association_name => "pages"},
        {:model => "Comment", :field => "body", :as => "comments", 
          :conditions => "comments.item_type = '#{base_class}'"}
      ],
      :conditions => self.live_condition_string
  end  

Note how setting the <tt>:conditions</tt> on Comment is enough to configure a polymorphic <tt>has_many</tt>.

== Association scoping

A common use case is to only search records that belong to a particular parent model. Ultrasphinx configures Sphinx to support a <tt>:raw_filters</tt> element on any date or numeric field, so any <tt>*_id</tt> fields you have will be filterable.

For example, say a Company <tt>has_many :users</tt> and each User <tt>has_many :articles</tt>. If you want to to filter Articles by Company, add <tt>company_id</tt> to the Article's <tt>is_indexed</tt> method. The best way is to grab it from the User association:

  class Article < ActiveRecord::Base 
     is_indexed :includes => [{:model => "User", :field => "company_id"}]
  end
 
Now you can run:

 @search = Ultrasphinx::Search.new(
   "something", 
   :raw_filters => {"company_id" => 493}
 )
 
If the associations weren't just <tt>has_many</tt> and <tt>belongs_to</tt>, you would need to use the <tt>:association_sql</tt> key to set up a custom JOIN. 

=end
  
    def self.is_indexed opts = {}
      opts.assert_valid_keys [:fields, :concats, :conditions, :includes, :nulls]
      
      Array(opts[:concats]).each do |concat|
        concat.assert_valid_keys [:model, :conditions, :field, :as, :fields, :association_name, :association_sql]
        raise Ultrasphinx::ConfigurationError, "You can't mix regular concat and group concats" if concat[:fields] and (concat[:field] or concat[:model] or concat[:association_name])
        raise Ultrasphinx::ConfigurationError, "Group concats must not have multiple fields" if concat[:field].is_a? Array
        raise Ultrasphinx::ConfigurationError, "Regular concats should have multiple fields" if concat[:fields] and !concat[:fields].is_a?(Array)
      end
      
      Array(opts[:includes]).each do |inc|
        inc.assert_valid_keys [:model, :field, :as, :association_sql]
      end
      
      Ultrasphinx::MODEL_CONFIGURATION[self.name] = opts
    end
  end
end
