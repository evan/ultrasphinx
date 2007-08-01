require File.dirname(__FILE__) + '/../init'

module SphinxFixtureHelper
  def sphinx_fixture(name)
    `php #{File.dirname(__FILE__)}/fixtures/#{name}.php`
  end
end

context 'The Connect method of SphinxApi' do
  setup do
    @sphinx = Sphinx::Client.new
    @sock = mock('TCPSocket')
  end

  specify 'should establish TCP connection to the server and initialize session' do
    TCPSocket.should_receive(:new).with('localhost', 3312).and_return(@sock)
    @sock.should_receive(:recv).with(4).and_return([1].pack('N'))
    @sock.should_receive(:send).with([1].pack('N'), 0)
    @sphinx.send(:Connect).should be(@sock)
  end

  specify 'should raise exception when searchd protocol is not 1+' do
    TCPSocket.should_receive(:new).with('localhost', 3312).and_return(@sock)
    @sock.should_receive(:recv).with(4).and_return([0].pack('N'))
    @sock.should_receive(:close)
    lambda { @sphinx.send(:Connect) }.should_raise(Sphinx::SphinxConnectError)
    @sphinx.GetLastError.should == 'expected searchd protocol version 1+, got version \'0\''
  end

  specify 'should raise exception on connection error' do
    TCPSocket.should_receive(:new).with('localhost', 3312).and_raise(Errno::EBADF)
    lambda { @sphinx.send(:Connect) }.should_raise(Sphinx::SphinxConnectError)
    @sphinx.GetLastError.should == 'connection to localhost:3312 failed'
  end

  specify 'should use custom host and port' do
    @sphinx.SetServer('anotherhost', 55555)
    TCPSocket.should_receive(:new).with('anotherhost', 55555).and_raise(Errno::EBADF)
    lambda { @sphinx.send(:Connect) }.should_raise(Sphinx::SphinxConnectError)
  end
end

context 'The GetResponse method of SphinxApi' do
  setup do
    @sphinx = Sphinx::Client.new
    @sock = mock('TCPSocket')
    @sock.should_receive(:close)
  end
  
  specify 'should receive response' do
    @sock.should_receive(:recv).with(8).and_return([Sphinx::Client::SEARCHD_OK, 1, 4].pack('n2N'))
    @sock.should_receive(:recv).with(4).and_return([0].pack('N'))
    @sphinx.send(:GetResponse, @sock, 1)
  end

  specify 'should raise exception on zero-sized response' do
    @sock.should_receive(:recv).with(8).and_return([Sphinx::Client::SEARCHD_OK, 1, 0].pack('n2N'))
    lambda { @sphinx.send(:GetResponse, @sock, 1) }.should_raise(Sphinx::SphinxResponseError)
  end

  specify 'should raise exception when response is incomplete' do
    @sock.should_receive(:recv).with(8).and_return([Sphinx::Client::SEARCHD_OK, 1, 4].pack('n2N'))
    @sock.should_receive(:recv).with(4).and_raise(EOFError)
    lambda { @sphinx.send(:GetResponse, @sock, 1) }.should_raise(Sphinx::SphinxResponseError)
  end

  specify 'should set warning message when SEARCHD_WARNING received' do
    @sock.should_receive(:recv).with(8).and_return([Sphinx::Client::SEARCHD_WARNING, 1, 14].pack('n2N'))
    @sock.should_receive(:recv).with(14).and_return([5].pack('N') + 'helloworld')
    @sphinx.send(:GetResponse, @sock, 1).should == 'world'
    @sphinx.GetLastWarning.should == 'hello'
  end

  specify 'should raise exception when SEARCHD_ERROR received' do
    @sock.should_receive(:recv).with(8).and_return([Sphinx::Client::SEARCHD_ERROR, 1, 9].pack('n2N'))
    @sock.should_receive(:recv).with(9).and_return([1].pack('N') + 'hello')
    lambda { @sphinx.send(:GetResponse, @sock, 1) }.should_raise(Sphinx::SphinxInternalError)
    @sphinx.GetLastError.should == 'searchd error: hello'
  end

  specify 'should raise exception when SEARCHD_RETRY received' do
    @sock.should_receive(:recv).with(8).and_return([Sphinx::Client::SEARCHD_RETRY, 1, 9].pack('n2N'))
    @sock.should_receive(:recv).with(9).and_return([1].pack('N') + 'hello')
    lambda { @sphinx.send(:GetResponse, @sock, 1) }.should_raise(Sphinx::SphinxTemporaryError)
    @sphinx.GetLastError.should == 'temporary searchd error: hello'
  end

  specify 'should raise exception when unknown status received' do
    @sock.should_receive(:recv).with(8).and_return([65535, 1, 9].pack('n2N'))
    @sock.should_receive(:recv).with(9).and_return([1].pack('N') + 'hello')
    lambda { @sphinx.send(:GetResponse, @sock, 1) }.should_raise(Sphinx::SphinxUnknownError)
    @sphinx.GetLastError.should == 'unknown status code: \'65535\''
  end

  specify 'should set warning when server is older than client' do
    @sock.should_receive(:recv).with(8).and_return([Sphinx::Client::SEARCHD_OK, 1, 9].pack('n2N'))
    @sock.should_receive(:recv).with(9).and_return([1].pack('N') + 'hello')
    @sphinx.send(:GetResponse, @sock, 5)
    @sphinx.GetLastWarning.should == 'searchd command v.0.1 older than client\'s v.0.5, some options might not work'
  end
end

context 'The Query method of SphinxApi' do
  include SphinxFixtureHelper

  setup do
    @sphinx = Sphinx::Client.new
    @sock = mock('TCPSocket')
    @sphinx.stub!(:Connect).and_return(@sock)
    @sphinx.stub!(:GetResponse).and_raise(Sphinx::SphinxError)
  end

  specify 'should generate valid request with default parameters' do
    expected = sphinx_fixture('default_search')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with default parameters and index' do
    expected = sphinx_fixture('default_search_index')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.Query('query', 'index') rescue nil?
  end
  
  specify 'should generate valid request with limits' do
    expected = sphinx_fixture('limits')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetLimits(10, 20)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with limits and max number to retrieve' do
    expected = sphinx_fixture('limits_max')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetLimits(10, 20, 30)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with match SPH_MATCH_ALL' do
    expected = sphinx_fixture('match_all')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetMatchMode(Sphinx::Client::SPH_MATCH_ALL)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with match SPH_MATCH_ANY' do
    expected = sphinx_fixture('match_any')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetMatchMode(Sphinx::Client::SPH_MATCH_ANY)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with match SPH_MATCH_PHRASE' do
    expected = sphinx_fixture('match_phrase')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetMatchMode(Sphinx::Client::SPH_MATCH_PHRASE)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with match SPH_MATCH_BOOLEAN' do
    expected = sphinx_fixture('match_boolean')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetMatchMode(Sphinx::Client::SPH_MATCH_BOOLEAN)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with match SPH_MATCH_EXTENDED' do
    expected = sphinx_fixture('match_extended')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetMatchMode(Sphinx::Client::SPH_MATCH_EXTENDED)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with sort mode SPH_SORT_RELEVANCE' do
    expected = sphinx_fixture('sort_relevance')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetSortMode(Sphinx::Client::SPH_SORT_RELEVANCE)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with sort mode SPH_SORT_ATTR_DESC' do
    expected = sphinx_fixture('sort_attr_desc')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetSortMode(Sphinx::Client::SPH_SORT_ATTR_DESC, 'sortby')
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with sort mode SPH_SORT_ATTR_ASC' do
    expected = sphinx_fixture('sort_attr_asc')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetSortMode(Sphinx::Client::SPH_SORT_ATTR_ASC, 'sortby')
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with sort mode SPH_SORT_TIME_SEGMENTS' do
    expected = sphinx_fixture('sort_time_segments')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetSortMode(Sphinx::Client::SPH_SORT_TIME_SEGMENTS, 'sortby')
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with sort mode SPH_SORT_EXTENDED' do
    expected = sphinx_fixture('sort_extended')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetSortMode(Sphinx::Client::SPH_SORT_EXTENDED, 'sortby')
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with weights' do
    expected = sphinx_fixture('weights')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetWeights([10, 20, 30, 40])
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with ID range' do
    expected = sphinx_fixture('id_range')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetIDRange(10, 20)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with values filter' do
    expected = sphinx_fixture('filter')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetFilter('attr', [10, 20, 30])
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with two values filters' do
    expected = sphinx_fixture('filters')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetFilter('attr2', [40, 50])
    @sphinx.SetFilter('attr1', [10, 20, 30])
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with values filter excluded' do
    expected = sphinx_fixture('filter_exclude')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetFilter('attr', [10, 20, 30], true)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with values filter range' do
    expected = sphinx_fixture('filter_range')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetFilterRange('attr', 10, 20)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with two filter ranges' do
    expected = sphinx_fixture('filter_ranges')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetFilterRange('attr2', 30, 40)
    @sphinx.SetFilterRange('attr1', 10, 20)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with filter range excluded' do
    expected = sphinx_fixture('filter_range_exclude')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetFilterRange('attr', 10, 20, true)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with different filters' do
    expected = sphinx_fixture('filters_different')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetFilterRange('attr1', 10, 20, true)
    @sphinx.SetFilter('attr3', [30, 40, 50])
    @sphinx.SetFilterRange('attr1', 60, 70)
    @sphinx.SetFilter('attr2', [80, 90, 100], true)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with group by SPH_GROUPBY_DAY' do
    expected = sphinx_fixture('group_by_day')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetGroupBy('attr', Sphinx::Client::SPH_GROUPBY_DAY)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with group by SPH_GROUPBY_WEEK' do
    expected = sphinx_fixture('group_by_week')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetGroupBy('attr', Sphinx::Client::SPH_GROUPBY_WEEK)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with group by SPH_GROUPBY_MONTH' do
    expected = sphinx_fixture('group_by_month')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetGroupBy('attr', Sphinx::Client::SPH_GROUPBY_MONTH)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with group by SPH_GROUPBY_YEAR' do
    expected = sphinx_fixture('group_by_year')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetGroupBy('attr', Sphinx::Client::SPH_GROUPBY_YEAR)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with group by SPH_GROUPBY_ATTR' do
    expected = sphinx_fixture('group_by_attr')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetGroupBy('attr', Sphinx::Client::SPH_GROUPBY_ATTR)
    @sphinx.Query('query') rescue nil?
  end

  specify 'should generate valid request with group by SPH_GROUPBY_DAY with sort' do
    expected = sphinx_fixture('group_by_day_sort')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.SetGroupBy('attr', Sphinx::Client::SPH_GROUPBY_DAY, 'somesort')
    @sphinx.Query('query') rescue nil?
  end
end

context 'The BuildExcerpts method of SphinxApi' do
  include SphinxFixtureHelper

  setup do
    @sphinx = Sphinx::Client.new
    @sock = mock('TCPSocket')
    @sphinx.stub!(:Connect).and_return(@sock)
    @sphinx.stub!(:GetResponse).and_raise(Sphinx::SphinxError)
  end
  
  specify 'should generate valid request with default parameters' do
    expected = sphinx_fixture('excerpt_default')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.BuildExcerpts(['10', '20'], 'index', 'word1 word2') rescue nil?
  end

  specify 'should generate valid request with custom parameters' do
    expected = sphinx_fixture('excerpt_custom')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.BuildExcerpts(['10', '20'], 'index', 'word1 word2', { 'before_match' => 'before',
                                                                  'after_match' => 'after',
                                                                  'chunk_separator' => 'separator',
                                                                  'limit' => 10 }) rescue nil?
  end
end

context 'The UpdateAttributes method of SphinxApi' do
  include SphinxFixtureHelper

  setup do
    @sphinx = Sphinx::Client.new
    @sock = mock('TCPSocket')
    @sphinx.stub!(:Connect).and_return(@sock)
    @sphinx.stub!(:GetResponse).and_raise(Sphinx::SphinxError)
  end
  
  specify 'should generate valid request' do
    expected = sphinx_fixture('update_attributes')
    @sock.should_receive(:send).with(expected, 0)
    @sphinx.UpdateAttributes('index', ['group'], { 123 => [456] }) rescue nil?
  end
end