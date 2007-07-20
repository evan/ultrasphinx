
require 'ultrasphinx'
require 'yaml'

module ActiveRecord
  class Base
    def self.is_indexed opts = {}
    
      opts.assert_valid_keys [:fields, :concats, :conditions, :includes, :nulls]
      
      Array(opts[:concats]).each do |concat|
        concat.assert_valid_keys [:model, :conditions, :field, :as, :fields, :association_name]
        raise Ultrasphinx::ConfigurationError, "You can't mix regular concat and group concats" if concat[:fields] and (concat[:field] or concat[:model] or concat[:association_name])
        raise Ultrasphinx::ConfigurationError, "Group concats must not have multiple fields" if concat[:field].is_a? Array
        raise Ultrasphinx::ConfigurationError, "Regular concats should have multiple fields" if concat[:fields] and !concat[:fields].is_a?(Array)
      end
      
      Array(opts[:joins]).each do |join|
        join.assert_valid_keys [:model, :field, :as]
      end
      
      Ultrasphinx::MODELS_HASH[self.name] = opts
    end
  end
end
