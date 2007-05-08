class SearchController < ApplicationController
  def index        
    
    params['search'] ||= {}
    @options = HashWithAccessorAccess.new((params['options'] || {}).reverse_merge({
      'models' => Search::MODELS.keys,
      'to' => 'now',
      'from' => '1 year ago',
      'page' => params[:page] || 1,
      'search_mode' => 'extended',
      'sort_mode' => 'desc',
      'sort_by' => 'published_at',
      'raw_filters' => {},
      'weights' => {"editorial" => (!params['weight'].blank? ? params['weight'].to_f : 2.0)}
    }))
    
    @options['raw_filters']['published_at'] = @options.from..@options.to 
    @search = Search.new(:sphinx, params['search']['query'], @options.no_pass('from', 'to'))
        
    begin
      unless (Chronic.parse(@options.to) and Chronic.parse(@options.from) rescue nil)
        @error = "Couldn't understand date range."
      else
        @search.excerpt unless @search.query.blank?
      end
    rescue Object => e
      raise unless e.is_a? Ultrasphinx::Exception
      @error = "Search error "
      @error += e.inspect + e.backtrace.inspect if Rails.development?
    end       
  end
  
end
