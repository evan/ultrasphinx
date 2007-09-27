
require 'rubygems'
require 'test/spec'
require 'ruby-debug'

Dir.chdir "#{File.dirname(__FILE__)}/app/" do
  system("rake db:migrate db:fixtures:load us:boot") if ENV['REINDEX']
  require 'config/environment'
end

class SmokeTest < Test::Unit::TestCase

  S = Ultrasphinx::Search

  def test_searchable
    assert_nothing_raised do
      @q = S.new(:query => 'seller').run
    end
    assert_equal 20, @q.results.size
  end  
  
  def test_run_with_no_query
    assert_nothing_raised do
      @q = S.new.run
    end
  end
  
  def test_sort_by_date
    assert_equal(
      Seller.find(:all, :limit => 5, :order => 'created_at DESC').map(&:created_at),
      S.new(:class_names => 'Seller', :sort_by => 'created_at', :sort_mode => 'descending', :per_page => 5).run.map(&:created_at)
    )
  end
 
  def test_filter
    assert_equal(
      Seller.count(:conditions => 'user_id = 17'),
      S.new(:class_names => 'Seller', :filters => {'user_id' => 17}).run.size
    )
  end
  
  def test_invalid_filter
    assert_raises(Sphinx::SphinxArgumentError) do
      S.new(:class_names => 'Seller', :filters => {'bogus' => 17}).run
    end
  end
  
end