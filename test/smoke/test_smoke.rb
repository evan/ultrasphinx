
require 'rubygems'
require 'test/spec'
require 'ruby-debug'

Dir.chdir "#{File.dirname(__FILE__)}/app/" do
#  unless `rake us:stat` =~ /running/
#    system("rake db:migrate db:fixtures:load us:boot")
#  end
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
    @q = S.new(:class_names => 'Seller', :sort_by => 'created_at', :sort_mode => 'ascending').run
    assert_equal((@q.results.map(&:created_at).sort), @q.results.map(&:created_at))

    @q = S.new(:class_names => 'Seller', :sort_by => 'created_at', :sort_mode => 'descending').run
    assert_not_equal((@q.results.map(&:created_at).sort), @q.results.map(&:created_at))
  end
 

end