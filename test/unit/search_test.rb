
require "#{File.dirname(__FILE__)}/../test_helper.rb"

describe "search object" do

  S = Ultrasphinx::Search
  
  it "parses the query" do
    S.new(:query => "field:content").instance_variable_get("@parsed_query").should.equal("@field content")
  end
  
end

