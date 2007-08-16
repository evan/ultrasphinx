
require "#{File.dirname(__FILE__)}/../test_helper.rb"

context "search object" do

  S = Ultrasphinx::Search

  it "rejects invalid keys" do
    should.raise(Sphinx::SphinxArgumentError) do
      S.new("query", :wrong => 1)
    end    
  end
  
  it "parses the query" do
    S.new("field:content").instance_variable_get("@parsed_query").should.equal("@field content")
  end

end

