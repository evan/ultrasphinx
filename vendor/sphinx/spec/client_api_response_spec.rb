require File.dirname(__FILE__) + '/../init'

# To execute these tests you need to execute sphinx_test.sql and configure sphinx using sphinx.conf
# (both files are placed under sphinx directory)
context 'The SphinxApi connected to Sphinx' do
  setup do
    @sphinx = Sphinx::Client.new
  end
  
  specify 'should parse response in Query method' do
    result = @sphinx.Query('wifi', 'test1')
    result['total_found'].should == 3
    result['matches'].length.should == 3
    result['time'].should_not be_nil
    result['attrs'].should == { 'group_id' => 1, 'created_at' => 2 }
    result['fields'].should == [ 'name', 'description' ]
    result['total'].should == 3
    result['matches'][1]['weight'].should == 1
    result['matches'][2]['weight'].should == 2
    result['matches'][3]['weight'].should == 2
    result['matches'][1]['attrs'].should == { 'group_id' => 1, 'created_at' => 1175658490 }
    result['matches'][2]['attrs'].should == { 'group_id' => 2, 'created_at' => 1175658555 }
    result['matches'][3]['attrs'].should == { 'group_id' => 1, 'created_at' => 1175658647 }
    result['words'].should == { 'wifi' => { 'hits' => 6, 'docs' => 3 } }
  end
  
  specify 'should parse response in BuildExcerpts method' do
    result = @sphinx.BuildExcerpts(['what the world', 'London is the capital of Great Britain'], 'test1', 'the')
    result.should == ['what <b>the</b> world', 'London is <b>the</b> capital of Great Britain']
  end

  specify 'should parse response in UpdateAttributes method' do
    @sphinx.UpdateAttributes('test1', ['group_id'], { 1 => [2] }).should == 1
    result = @sphinx.Query('wifi', 'test1')
    result['matches'][1]['attrs']['group_id'].should == 2
    @sphinx.UpdateAttributes('test1', ['group_id'], { 1 => [1] }).should == 1
    result = @sphinx.Query('wifi', 'test1')
    result['matches'][1]['attrs']['group_id'].should == 1
  end
end
