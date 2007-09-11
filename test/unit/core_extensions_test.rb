
require "#{File.dirname(__FILE__)}/../test_helper.rb"

context "hashes should" do

  it "stringify deeply" do
    {:dog => 'woof', :cat => ['meow', {:action => 'scratch'}]}._deep_stringify_keys.should.equal(
      {'dog' => 'woof', 'cat' => ['meow', {'action' => 'scratch'}]}
    )
  end

end

