class SearchController < ApplicationController

  def index            
    params['search'] ||= {}
    @options = HashWithAccessorAccess.new((params['options'] || {}).reverse_merge({
      'models' => nil,
      'to' => 'now',
      'from' => '1 year ago',
      'page' => params[:page] || 1,
      'search_mode' => 'extended',
      'sort_mode' => 'desc',
      'sort_by' => 'created_at',
      'raw_filters' => {},
      'weights' => {
        "title" => 2.0 
      }
    }))
    
    @options['raw_filters']['published_at'] = @options.from..@options.to 
    @search = Ultrasphinx::Search.new(params['search']['query'], @options.except('from', 'to'))
        
    unless (Chronic.parse(@options.to) and Chronic.parse(@options.from) rescue nil)
      @error = "Couldn't understand date range."
    else
      @search.excerpt unless @search.query.blank?
    end

  end
  
end
