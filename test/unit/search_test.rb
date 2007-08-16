
require "#{File.dirname(__FILE__)}/../test_helper.rb"

context "search object" do

  S = Ultrasphinx::Search

  it "rejects invalid keys" do
    should.raise(Sphinx::SphinxArgumentError) do
      S.new("query", :wrong => 1)
    end    
  end

end

