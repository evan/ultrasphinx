
module Ultrasphinx

=begin rdoc
Command-interface Search object.

== Basic usage
  
To set up a search, instantiate an Ultrasphinx::Search object with a hash of parameters. Only the <tt>'query'</tt> key is mandatory.
  @search = Ultrasphinx::Search.new(
    'query' => @query, 
    'sort_mode' => 'descending', 
    'sort_by' => 'created_at'
  )
    
Now, to run the query, call its <tt>run</tt> method. Your results will be available as ActiveRecord instances via the <tt>results</tt> method. Example:  
  @search.run
  @search.results

= Options

== Query format

The query string supports boolean operation, parentheses, phrases, and field-specific search. Query words are stemmed and joined by an implicit <tt>AND</tt> by default.

* Valid boolean operators are <tt>AND</tt>, <tt>OR</tt>, and <tt>NOT</tt>.
* Field-specific searches should be formatted as <tt>fieldname:contents</tt>. (This will only work for text fields. For numeric and date fields, see the <tt>'filters</tt> parameter, below.)
* Phrases must be enclosed in double quotes.
    
A Sphinx::SphinxInternalError will be raised on invalid queries. In general, queries can only be nested to one level. 
  @query = 'dog OR cat OR "white tigers" NOT (lions OR bears) AND title:animals'

== Hash parameters

The hash lets you customize internal aspects of the search.

<tt>'per_page'</tt>:: An integer. How many results per page.
<tt>'page'</tt>:: An integer. Which page of the results to return.
<tt>'class_name'</tt>:: An array or string. The class name of the model you want to search, an array of model names to search, or <tt>nil</tt> for all available models.    
<tt>'sort_mode'</tt>:: 'relevance' or 'ascending' or 'descending'. How to order the result set. Note that 'time' and 'extended' modes are available, but not tested.  
<tt>'sort_by'</tt>:: A field name. What field to order by for 'ascending' or 'descending' mode. Has no effect for 'relevance'.
<tt>'weight'</tt>:: A hash. Text-field names and associated query weighting. The default weight for every field is 1.0. Example: <tt>'weight' => {'title' => 2.0}</tt>
<tt>'filter'</tt>:: A hash. Names of numeric or date fields and associated values. You can use a single value, an array of values, or a range. (See the bottom of the ActiveRecord::Base page for an example.)
<tt>'facets'</tt>:: An array of fields for grouping/faceting. You can access the returned facet values and their result counts with the <tt>facets</tt> method.

Note that you can set up your own query defaults in <tt>environment.rb</tt>: 
  
  Ultrasphinx::Search.query_defaults = {
    'per_page' => 10,
    'sort_mode' => 'relevance',
    'weight' => {'title' => 2.0}
  }

= Advanced features

== Cache_fu integration
  
The <tt>get_cache</tt> method will be used to instantiate records for models that respond to it. Otherwise, <tt>find</tt> is used.

== Will_paginate integration

The Search instance responds to the same methods as a WillPaginate::Collection object, so once you have called <tt>run</tt> or <tt>excerpt</tt> you can use it directly in your views:

  will_paginate(@search)

== Excerpt mode

You can have Sphinx excerpt and highlight the matched sections in the associated fields. Instead of calling <tt>run</tt>, call <tt>excerpt</tt>. 
  
  @search.excerpt

The returned models will be frozen and have their field contents temporarily changed to the excerpted and highlighted results. 
  
You need to set the <tt>content_methods</tt> key on Ultrasphinx::Search.excerpting_options to whatever groups of methods you need the excerpter to try to excerpt. The first responding method in each group for each record will be excerpted. This way Ruby-only methods are supported (for example, a metadata method which combines various model fields, or an aliased field so that the original record contents are still available).
  
There are some other keys you can set, such as excerpt size, HTML tags to highlight with, and number of words on either side of each excerpt chunk. Example (in <tt>environment.rb</tt>):
  
  Ultrasphinx::Search.excerpting_options = {
    'before_match' => '<strong>', 
    'after_match' => '</strong>',
    'chunk_separator' => "...",
    'limit' => 256,
    'around' => 3,
    'content_methods' => [['title'], ['body', 'description', 'content'], ['metadata']] 
  }
  
Note that your database is never changed by anything Ultrasphinx does.

=end    

  class Search  
  
    include Internals
    include Parser
    
    cattr_accessor :query_defaults  
    self.query_defaults ||= {
      'query' => nil,
      'page' => 1,
      'class_name' => nil,
      'per_page' => 20,
      'sort_by' => 'created_at',
      'sort_mode' => 'relevance',
      'weight' => nil,
      'filter' => nil,
      'facets' => nil
    }
    
    cattr_accessor :excerpting_options
    self.excerpting_options ||= {
      'before_match' => "<strong>", 'after_match' => "</strong>",
      'chunk_separator' => "...",
      'limit' => 256,
      'around' => 3,
      # results should respond to one in each group of these, in precedence order, for the excerpting to fire
      'content_methods' => [['title', 'name'], ['body', 'description', 'content'], ['metadata']] 
    }
    
    cattr_accessor :client_options
    self.client_options ||= { 
      'with_subtotals' => false, 
      'max_retries' => 4,
      'retry_sleep_time' => 3,
      'max_facets' => 100,
      'finder_methods' => ['get_cache', 'find']
    }
    
    # mode to integer mappings    
    SPHINX_CLIENT_PARAMS = { 
      'sort_mode' => {
        'relevance' => Sphinx::Client::SPH_SORT_RELEVANCE, 
        'descending' => Sphinx::Client::SPH_SORT_ATTR_DESC, 
        'ascending' => Sphinx::Client::SPH_SORT_ATTR_ASC, 
        'time' => Sphinx::Client::SPH_SORT_TIME_SEGMENTS,
        'extended' => Sphinx::Client::SPH_SORT_EXTENDED,
        'desc' => Sphinx::Client::SPH_SORT_ATTR_DESC, # legacy compatibility
        'asc' => Sphinx::Client::SPH_SORT_ATTR_ASC
      }
    }
    
    LEGACY_QUERY_KEYS = ['raw_filters'] #:nodoc:
    
    INTERNAL_KEYS = ['parsed_query'] #:nodoc:

    def self.get_models_to_class_ids #:nodoc:
      # reading the conf file makes sure that we are in sync with the actual sphinx index,
      # not whatever you happened to change your models to most recently
      unless File.exist? CONF_PATH
        Ultrasphinx.say "configuration file not found for #{RAILS_ENV.inspect} environment"
        Ultrasphinx.say "please run 'rake ultrasphinx:configure'"
      else
        begin  
          lines = open(CONF_PATH).readlines          
          sources = lines.select {|s| s =~ /^source \w/ }.map {|s| s[/source ([\w\d_-]*)/, 1].classify }
          ids = lines.select {|s| s =~ /^sql_query / }.map {|s| s[/(\d*) AS class_id/, 1].to_i }
          
          raise unless sources.size == ids.size          
          Hash[*sources.zip(ids).flatten]
                                  
        rescue
          Ultrasphinx.say "#{CONF_PATH} file is corrupted"
          Ultrasphinx.say "please run 'rake ultrasphinx:configure'"
        end    
        
      end
    end

    MODELS_TO_IDS = get_models_to_class_ids || {} 
      
    MAX_MATCHES = DAEMON_SETTINGS["max_matches"].to_i 
    
    FACET_CACHE = {} #:nodoc: 
    
    # Returns the options hash.
    def options
      @options
    end
    
    #  Returns the query string used.
    def query
      # redundant with method_missing
      @options['query']
    end
    
    def parsed_query #:nodoc:
      # redundant with method_missing
      @options['parsed_query']
    end
    
    # Returns an array of result objects.
    def results
      run?(true)
      @results
    end
    
    def facets
      raise UsageError, "No facet field was configured" unless @options['facets']
      run?(true)
      @facets
    end      
      
    
    # Returns the raw response from the Sphinx client.
    def response
      @response
    end
    
    # Returns a hash of total result counts, scoped to each available model. This requires extra queries against the search daemon right now. Set <tt>Ultrasphinx::Search.client_options['with_subtotals'] = true</tt> to enable the extra queries. Most of the overhead is in instantiating the AR result sets, so the performance hit is not usually significant.
    def subtotals
      raise UsageError, "Subtotals are not enabled" unless self.class.client_options['with_subtotals']
      @subtotals
    end

    # Returns the total result count.
    def total_entries
      [response['total_found'] || 0, MAX_MATCHES].min
    end  
  
    # Returns the response time of the query, in milliseconds.
    def time
      response['time']
    end

    # Returns whether the query has been run.  
    def run?(should_raise = false)
      if response.blank? and should_raise
        raise UsageError, "Search has not yet been run" unless run?
      else
        !response.blank?
      end
    end
 
    # Returns the current page number of the result set. (Page indexes begin at 1.) 
    def current_page
      @options['page']
    end
  
    # Returns the number of records per page.
    def per_page
      @options['per_page']
    end
        
    # Returns the last available page number in the result set.  
    def page_count
      (total_entries / per_page) + (total_entries % per_page == 0 ? 0 : 1)
    end
            
    # Returns the previous page number.
    def previous_page 
      current_page > 1 ? (current_page - 1) : nil
    end

    # Returns the next page number.
    def next_page
      current_page < page_count ? (current_page + 1) : nil
    end
    
    # Returns the global index position of the first result on this page.
    def offset 
      (current_page - 1) * per_page
    end    
    
    # Builds a new command-interface Search object.
    def initialize opts = {}
      
      opts = opts._deep_stringify_keys
            
      @options = self.class.query_defaults.merge(opts._deep_dup._coerce_basic_types)

      @options['filter'] ||= @options['raw_filters'] || {} # XXX legacy name

      @options['query'] = @options['query'].to_s
      @options['class_name'] = Array(@options['class_name'])
      
      @options['parsed_query'] = if query.blank? 
         "@empty_searchable #{EMPTY_SEARCHABLE}"
        else
          parse(query)
        end
  
      @results, @subtotals, @facets, @response = [], {}, {}, {}
        
      extra_keys = @options.keys - (SPHINX_CLIENT_PARAMS.merge(self.class.query_defaults).keys + LEGACY_QUERY_KEYS + INTERNAL_KEYS)
      say "discarded invalid keys: #{extra_keys * ', '}" if extra_keys.any?
    end
    
    # Run the search, filling results with an array of ActiveRecord objects. Set the parameter to false if you only want the ids returned.
    def run(reify = true)
      @request = build_request_with_options(@options)
      @paginate = nil # clear cache
      tries = 0

      say "searching for #{@options.inspect}"

      begin
              
        @response = @request.Query(parsed_query)
        say "search returned, error #{@request.GetLastError.inspect}, warning #{@request.GetLastWarning.inspect}, returned #{total_entries}/#{response['total_found']} in #{time} seconds."  

        @subtotals = get_subtotals(@request, parsed_query) if self.class.client_options['with_subtotals']
        
        Array(@options['facets']).each do |facet|
          @facets[facet] = get_facets(@request, parsed_query, facet)
        end
        
        @results = response['matches']
        
        # if you don't reify, you'll have to do the modulus reversal yourself to get record ids
        @results = reify_results(@results) if reify
                                
      rescue Sphinx::SphinxResponseError, Sphinx::SphinxTemporaryError, Errno::EPIPE => e
        if (tries += 1) <= self.class.client_options['max_retries']
          say "restarting query (#{tries} attempts already) (#{e})"
          sleep(self.class.client_options['retry_sleep_time']) if tries == self.class.client_options['max_retries']
          retry
        else
          say "query failed"
          raise e
        end
      end
      
      self
    end
  
  
    # Overwrite the configured content accessors with excerpted and highlighted versions of themselves.
    # Runs run if it hasn't already been done.
    def excerpt
    
      run unless run?         
      return if results.empty?
    
      # see what fields each result might respond to for our excerpting
      results_with_content_methods = results.map do |result|
        [result] << self.class.excerpting_options['content_methods'].map do |methods|
          methods.detect { |x| result.respond_to? x }
        end
      end
  
      # fetch the actual field contents
      texts = results_with_content_methods.map do |result, methods|
        methods.map do |method| 
          method and strip_bogus_characters(result.send(method)) or ""
        end
      end.flatten
  
      # ship to sphinx to highlight and excerpt
      responses = @request.BuildExcerpts(
        texts, 
        UNIFIED_INDEX_NAME, 
        strip_query_commands(parsed_query),
        self.class.excerpting_options.except('content_methods')
      ).in_groups_of(self.class.excerpting_options['content_methods'].size)
      
      results_with_content_methods.each_with_index do |result_and_methods, i|
        # override the individual model accessors with the excerpted data
        result, methods = result_and_methods
        methods.each_with_index do |method, j|
          result._metaclass.send('define_method', method) { responses[i][j] } if method
        end
      end
  
      @results = results_with_content_methods.map do |result_and_content_method| 
        result_and_content_method.first.freeze
      end
      
      self
    end  
    
            
    # Delegates enumerable methods to @results, if possible. This allows us to behave directly like a WillPaginate::Collection. Failing that, we delegate to the options hash if a key is set. This lets us use the <tt>self</tt> directly in view helpers.
    def method_missing(*args, &block)
      if @results.respond_to? args.first
        @results.send(*args, &block)
      elsif options.has_key? args.first.to_s
        @options[args.first.to_s]
      else
        super
      end
    end
  
    def say msg #:nodoc:
      Ultrasphinx.say msg
    end
    
  end
end
