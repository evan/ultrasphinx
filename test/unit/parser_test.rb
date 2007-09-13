
require "#{File.dirname(__FILE__)}/../test_helper.rb"

context "parser" do

  def setup
    @s = Ultrasphinx::Search.new
  end

  [
  'artichokes', 
  'artichokes',
    
    '  artichokes  ', 
    'artichokes',
    
    'artichoke heart', 
    'artichoke heart',
    
    '"artichoke hearts"', 
    '"artichoke hearts"',
    
    '  "artichoke hearts  " ', 
    '"artichoke hearts"',
    
    'artichoke AND hearts', 
    'artichoke hearts',
    
    'artichoke OR hearts', 
    'artichoke | hearts',
    
    'artichoke NOT heart', 
    'artichoke - heart',

    'artichoke and hearts', 
    'artichoke hearts',
    
    'artichoke or hearts', 
    'artichoke | hearts',
    
    'artichoke not heart', 
    'artichoke - heart',
    
    'title:artichoke', 
    '@title artichoke',
    
    'user:"john mose"', 
    '@user "john mose"',
    
    'artichoke OR rhubarb NOT heart user:"john mose"', 
    'artichoke | rhubarb - heart @user "john mose"',
    
    'title:artichoke hearts', 
    'hearts @title artichoke',

    'title:artichoke AND hearts', 
    'hearts @title artichoke',
    
    'title:artichoke NOT hearts', 
    'hearts - @title artichoke',

    'title:artichoke OR hearts', 
    'hearts | @title artichoke',

    'title:artichoke title:hearts', 
    '@title ( artichoke hearts )',

    'title:artichoke OR title:hearts', 
    '@title ( artichoke | hearts )',

    'title:artichoke NOT title:hearts "john mose" ', 
    '"john mose" @title ( artichoke - hearts )',

    '"john mose" AND title:artichoke dogs OR title:hearts cats', 
    '"john mose" dogs cats @title ( artichoke | hearts )',
    
    'board:england OR board:tristate',
    '@board ( england | tristate )',
    
    '(800) 555-LOVE',
    '(800) 555-LOVE',
    
    'Bend, OR',
    'Bend, OR'
    
  ].in_groups_of(2).each do |query, result|
    it "should parse" do
      @s.send(:parse, query).should.equal(result)
    end
  end

end

