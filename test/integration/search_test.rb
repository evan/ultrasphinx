
require "#{File.dirname(__FILE__)}/../test_helper"

class SearchTest < Test::Unit::TestCase

  S = Ultrasphinx::Search
  E = Ultrasphinx::UsageError
  STRFTIME = "%b %d %Y %H:%M:%S" # Chronic can't parse the default date .to_s

  def test_simple_query
    assert_nothing_raised do
      @s = S.new(:query => 'seller').run
    end
    assert_equal 20, @s.results.size
  end  
  
  def test_query_must_be_run
    @s = S.new
    assert_raises(E) { @s.total_entries }
    assert_raises(E) { @s.response }
    assert_raises(E) { @s.facets }
    assert_raises(E) { @s.results }
  end
  
  def test_subtotals
    @s = S.new.run
    assert_equal @s.total_entries, @s.subtotals.values._sum
  end
  
  def test_query_retries_and_fails
    system("cd #{RAILS_ROOT}; rake ultrasphinx:daemon:stop &> /dev/null")
    assert_raises(Sphinx::SphinxConnectError) do
      S.new.run
    end
    system("cd #{RAILS_ROOT}; rake ultrasphinx:daemon:start &> /dev/null")
  end
  
  def test_accessors
    @per_page = 5
    @page = 3
    @s = S.new(:query => 'seller', :per_page => @per_page, :page => @page).run
    assert_equal @per_page, @s.per_page
    assert_equal @page, @s.page
    assert_equal @page - 1, @s.previous_page
    assert_equal @page + 1, @s.next_page
    assert_equal @per_page * (@page - 1), @s.offset
    assert @s.page_count >= @s.total_entries / @per_page.to_f
   end
  
  def test_empty_query
    @total = Ultrasphinx::MODEL_CONFIGURATION.keys.inject(0) do |acc, class_name| 
      acc + class_name.constantize.count
    end - User.count(:conditions => {:deleted => true })
    
    assert_nothing_raised do
      @s = S.new.run
    end
    
    assert_equal(
      @total,
      @s.total_entries
    )
  end
  
  def test_sort_by_date
    assert_equal(
      Seller.find(:all, :limit => 5, :order => 'created_at DESC').map(&:created_at),
      S.new(:class_names => 'Seller', :sort_by => 'created_at', :sort_mode => 'descending', :per_page => 5).run.map(&:created_at)
    )
  end

  def test_sort_by_float
    assert_equal(
      Seller.find(:all, :limit => 5, :order => 'capitalization ASC').map(&:capitalization),
      S.new(:class_names => 'Seller', :sort_by => 'capitalization', :sort_mode => 'ascending', :per_page => 5).run.map(&:capitalization)
    )
  end
 
  def test_filter
    assert_equal(
      Seller.count(:conditions => 'user_id = 17'),
      S.new(:class_names => 'Seller', :filters => {'user_id' => 17}).run.size
    )
  end
  
  def test_nil_filter
    # XXX
  end
  
  def test_float_range_filter
    @count = Seller.count(:conditions => 'capitalization <= 29.5 AND capitalization >= 10')
    assert_equal(@count,
      S.new(:class_names => 'Seller', :filters => {'capitalization' => 10..29.5}).run.size)
    assert_equal(@count,
      S.new(:class_names => 'Seller', :filters => {'capitalization' => 29.5..10}).run.size)
  end

  def test_date_range_filter
    @first, @last = Seller.find(5).created_at, Seller.find(10).created_at
    @count = Seller.count(:conditions => ['created_at <= ? AND created_at >= ?', @first, @last])
    assert_equal(@count,
      S.new(:class_names => 'Seller', :filters => {'created_at' => @first..@last}).run.size)
    assert_equal(@count,
      S.new(:class_names => 'Seller', :filters => {'created_at' => @last..@first}).run.size)
    assert_equal(@count,
      S.new(:class_names => 'Seller', :filters => {'created_at' => @last.strftime(STRFTIME)...@first.strftime(STRFTIME)}).run.size)

    assert_raises(Ultrasphinx::UsageError) do
      S.new(:class_names => 'Seller', :filters => {'created_at' => "bogus".."sugob"}).run.size
    end
  end
    
  def test_text_filter
    assert_equal(
      Seller.count(:conditions => "company_name = 'seller17'"),
      S.new(:class_names => 'Seller', :filters => {'company_name' => 'seller17'}).run.size
    )  
  end
  
  def test_invalid_filter
    assert_raises(Sphinx::SphinxArgumentError) do
      S.new(:class_names => 'Seller', :filters => {'bogus' => 17}).run
    end
  end
  
  def test_conditions
    @deleted_count = User.count(:conditions => {:deleted => true })
    assert_equal 1, @deleted_count
    assert_equal User.count - @deleted_count, S.new(:class_name => 'User').run.total_entries 
  end
  
#  def test_mismatched_facet_configuration
#    assert_raises(Ultrasphinx::ConfigurationError) do 
#      Ultrasphinx::Search.new(:facets => 'company_name').run
#    end
#  end
  
  def test_bogus_facet_name
    assert_raises(Ultrasphinx::UsageError) do
      Ultrasphinx::Search.new(:facets => 'bogus').run
    end
  end  
  
  def test_text_facet
    @s = Ultrasphinx::Search.new(:facets => ['company_name']).run
    assert_equal 21, @s.facets['company_name'].size
  end
  
  def test_numeric_facet
    @s = Ultrasphinx::Search.new(:facets => 'user_id').run
    assert_equal Geo::Address.count + 1, @s.facets['user_id'].size
    assert @s.facets['user_id'][0] > 1
  end
  
  def test_multi_facet
    # XXX
  end
  
  def test_association_sql
    # XXX
  end
    
  def test_weights
    @unweighted = Ultrasphinx::Search.new(:query => 'seller1', :per_page => 1).run.first
    @weighted = Ultrasphinx::Search.new(:query => 'seller1', :weights => {'company' => 2}, :per_page => 1).run.first
    assert_not_equal @unweighted.class, @weighted.class
  end
  
  def test_excerpts
    @s = Ultrasphinx::Search.new(:query => 'seller10')
    @excerpted_item = @s.excerpt.first
    @item = @s.run.first
    assert_not_equal @item.name, @excerpted_item.name
    assert_match /strong/, @excerpted_item.name
  end
  
end