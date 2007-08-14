
module Ultrasphinx

=begin rdoc
Command-interface Search object.

== Basic usage
  
To set up a search, instantiate an Ultrasphinx::Search object. Parameters are the query string, and an optional hash of query options.  
  @search = Ultrasphinx::Search.new(
    @query, 
    :sort_mode => 'descending', 
    :sort_by => 'created_at'
  )
    
Now, to run the query, call its <tt>run()</tt> method. Your results will be available as ActiveRecord instances via the <tt>results</tt> method. Example:  
  @search.run
  @search.results

= Options

== Query format

The query string supports boolean operation, parentheses, phrases, and field-specific search. Query words are stemmed and joined by an implicit <tt>AND</tt> by default.

* Valid boolean operators are <tt>AND</tt>, <tt>OR</tt>, and <tt>NOT</tt>.
* Field-specific searches should be formatted as <tt>fieldname:contents</tt>
* Phrases must be enclosed in double quotes.
    
A Sphinx::SphinxInternalError will be raised on invalid queries. In general, queries can only be nested to one level. 
  @query = 'dog OR cat OR "white tigers" NOT (lions OR bears) AND title:animals'

== Hash parameters

The hash lets you customize internal aspects of the search.

<tt>:per_page</tt>:: An integer. How many results per page.
<tt>:page</tt>:: An integer. Which page of the results to return.
<tt>:models</tt>:: An array or string. The class name of the model you want to search, an array of model names to search, or <tt>nil</tt> for all available models.    
<tt>:sort_mode</tt>:: 'relevance' or 'ascending' or 'descending'. How to order the result set. Note that 'time' and 'extended' modes are available, but not tested.  
<tt>:sort_by</tt>:: A field name. What field to order by for 'ascending' or 'descending' mode. Has no effect for 'relevance'.
<tt>:weights</tt>:: A hash. Text-field names and associated query weighting. The default weight for every field is 1.0. Example: <tt>:weights => {"title" => 2.0}</tt>
<tt>:raw_filters</tt>:: A hash. Field names and associated numeric values. You can use a single value, an array of values, or a range. 

Note that you can set up your own query defaults in <tt>environment.rb</tt>: 
  
  Ultrasphinx::Search.query_defaults = {
    :per_page => 10,
    :sort_mode => :relevance,
    :weights => {"title" => 2.0}
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
    'before_match' => "<strong>", 
    'after_match' => "</strong>",
    'chunk_separator' => "...",
    'limit' => 256,
    'around' => 3,
    'content_methods' => [['title'], ['body', 'description', 'content'], ['metadata']] 
  }
  
Note that your database is never changed by anything Ultrasphinx does.

=end    

  class Search  
    
    cattr_accessor :query_defaults  
    self.query_defaults ||= {:page => 1,
      :models => nil,
      :per_page => 20,
      :sort_by => 'created_at',
      :sort_mode => :relevance,
      :weights => nil,
      :raw_filters => nil}
    
    cattr_accessor :excerpting_options
    self.excerpting_options ||= {
      'before_match' => "<strong>", 'after_match' => "</strong>",
      'chunk_separator' => "...",
      'limit' => 256,
      'around' => 3,
      # results should respond to one in each group of these, in precedence order, in order for the excerpting to fire
      'content_methods' => [[:title, :name], [:body, :description, :content], [:metadata]] 
    }
    
    cattr_accessor :client_options
    self.client_options ||= { 
      :with_subtotals => false, 
      :max_retries => 4,
      :retry_sleep_time => 3
    }
    
    # mode to integer mappings    
    SPHINX_CLIENT_PARAMS = { 
      :sort_mode => {
        :relevance => Sphinx::Client::SPH_SORT_RELEVANCE, 
        :descending => Sphinx::Client::SPH_SORT_ATTR_DESC, 
        :ascending => Sphinx::Client::SPH_SORT_ATTR_ASC, 
        :time => Sphinx::Client::SPH_SORT_TIME_SEGMENTS,
        :extended => Sphinx::Client::SPH_SORT_EXTENDED,
        :desc => Sphinx::Client::SPH_SORT_ATTR_DESC, # legacy compatibility
        :asc => Sphinx::Client::SPH_SORT_ATTR_ASC
      }
    }

    def self.get_models_to_class_ids #:nodoc:
      # reading the conf file makes sure that we are in sync with the actual sphinx index,
      # not whatever you happened to change your models to most recently
      unless File.exist? CONF_PATH
        Ultrasphinx.say "configuration file not found for #{ENV['RAILS_ENV'].inspect} environment"
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
    
    # Returns the options hash you used.
    def options; @options; end
    
    #  Returns the query string used.
    def query; @query; end
    
    # Returns an array of result objects.
    def results
      raise UsageError, "Search has not yet been run" unless run?
      @results
    end
    
    # Returns the raw response from the Sphinx client.
    def response; @response; end
    
    # Returns a hash of total result counts, scoped to each available model. This requires extra queries against the search daemon right now. Set <tt>Ultrasphinx::Search.client_options[:with_subtotals] = true</tt> to enable the extra queries. Most of the overhead is in instantiating the AR result sets, so the performance hit is not usually significant.
    def subtotals
      raise UsageError, "Subtotals are not enabled" unless self.class.client_options[:with_subtotals]
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
    def run?
      !response.blank?
    end
 
    # Returns the current page number of the result set. (Page indexes begin at 1.) 
    def current_page
      options[:page]
    end
  
    # Returns the number of records per page.
    def per_page
      options[:per_page]
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
    def initialize query, opts = {}                
      @query = query || ""
      @parsed_query = parse_google_to_sphinx(@query)
        
      @options = self.class.query_defaults.merge(opts._coerce_basic_types)        
      @options[:raw_filters] ||= {}
      @options[:models] = Array(@options[:models])
  
      @results, @subtotals, @response = [], {}, {}
              
      raise Sphinx::SphinxArgumentError, "Invalid options: #{@extra * ', '}" if (@extra = (@options.keys - (SPHINX_CLIENT_PARAMS.merge(self.class.query_defaults).keys))).size > 0      
    end
    
    # Run the search, filling results with an array of ActiveRecord objects.
    def run(reify = true)      
      @request = build_request_with_options(@options)
      @paginate = nil # clear cache
      tries = 0

      logger.info "** ultrasphinx: searching for #{query.inspect} (parsed as #{@parsed_query.inspect}), options #{@options.inspect}"

      begin
        @response = @request.Query(@parsed_query)
        logger.info "** ultrasphinx: search returned, error #{@request.GetLastError.inspect}, warning #{@request.GetLastWarning.inspect}, returned #{total_entries}/#{response['total_found']} in #{time} seconds."  

        @subtotals = get_subtotals(@request, @parsed_query) if self.class.client_options[:with_subtotals]
        @results = response['matches']
        
        # if you don't reify, you'll have to do the modulus reversal yourself to get record ids
        @results = reify_results(@results) if reify
                  
      rescue Sphinx::SphinxResponseError, Sphinx::SphinxTemporaryError, Errno::EPIPE => e
        if (tries += 1) <= self.class.client_options[:max_retries]
          logger.warn "** ultrasphinx: restarting query (#{tries} attempts already) (#{e})"
          sleep(self.class.client_options[:retry_sleep_time]) if tries == self.class.client_options[:max_retries]
          retry
        else
          logger.warn "** ultrasphinx: query failed"
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
        strip_query_commands(@parsed_query),
        self.class.excerpting_options.except('content_methods')
      ).in_groups_of(self.class.excerpting_options['content_methods'].size)
      
      results_with_content_methods.each_with_index do |result_and_methods, i|
        # override the individual model accessors with the excerpted data
        result, methods = result_and_methods
        methods.each_with_index do |method, j|
          result._metaclass.send(:define_method, method) { responses[i][j] } if method
        end
      end
  
      @results = results_with_content_methods.map(&:first).map(&:freeze)
      
      self
    end  
    
  
    private
    
    def build_request_with_options opts

      request = Sphinx::Client.new

      request.SetServer(PLUGIN_SETTINGS['server_host'], PLUGIN_SETTINGS['server_port'])
      request.SetMatchMode Sphinx::Client::SPH_MATCH_EXTENDED # force extended query mode

      offset, limit = opts[:per_page] * (opts[:page] - 1), opts[:per_page]
      
      request.SetLimits offset, limit, [offset + limit, MAX_MATCHES].min
      request.SetSortMode SPHINX_CLIENT_PARAMS[:sort_mode][opts[:sort_mode]], opts[:sort_by].to_s

      if weights = opts[:weights]
        # order the weights hash according to the field order for sphinx, and set the missing fields to 1.0
        # XXX we shouldn't really have to hit Fields.instance from within Ultrasphinx::Search
        request.SetWeights(Fields.instance.select{|n,t| t == 'text'}.map(&:first).sort.inject([]) do |array, field|
          array << (weights[field] || 1.0)
        end)
      end

      unless opts[:models].compact.empty?
        request.SetFilter 'class_id', opts[:models].map{|m| MODELS_TO_IDS[m.to_s]}
      end        

      # extract ranged raw filters 
      # XXX some of this mangling might not be necessary
      opts[:raw_filters].each do |field, value|
        begin
          unless value.is_a? Range
            request.SetFilter field, Array(value)
          else
            min, max = [value.first, value.last].map do |x|
              x._to_numeric if x.is_a? String
            end
            unless min.class != max.class
              min, max = max, min if min > max
              request.SetFilterRange field, min, max
            end
          end
        rescue NoMethodError => e
          raise Sphinx::SphinxArgumentError, "filter: #{field.inspect}:#{value.inspect} is invalid"
        end
      end
      
      # request.SetIdRange # never useful
      # request.SetGroup # never useful
      
      request
    end    
  
    def get_subtotals(request, query)
      # XXX andrew says there's a better way to do this
      subtotals, filtered_request = {}, request.dup
      
      MODELS_TO_IDS.each do |name, class_id|
        filtered_request.instance_eval { @filters.delete_if {|f| f['attr'] == 'class_id'} }
        filtered_request.SetFilter 'class_id', [class_id]
        subtotals[name] = request.Query(query)['total_found']
      end
      
      subtotals
    end

    def strip_bogus_characters(s)
      # used to remove some garbage before highlighting
      s.gsub(/<.*?>|\.\.\.|\342\200\246|\n|\r/, " ").gsub(/http.*?( |$)/, ' ') if s
    end
    
    def strip_query_commands(s)
      # XXX dumb hack for query commands, since sphinx doesn't intelligently parse the query in excerpt mode
      s.gsub(/AND|OR|NOT|\@\w+/, "")
    end 
  
    def parse_google_to_sphinx query
      # alters google-style querystring into sphinx-style
      return if query.blank?

      # remove AND's, always
      query = " #{query} ".gsub(" AND ", " ")

      # split query on spaces that are not inside sets of quotes or parens
      query = query.scan(/[^"() ]*["(][^")]*[")]|[^"() ]+/) 

      query.each_with_index do |token, index|
      
        # recurse for parens, if necessary
        if token =~ /^(.*?)\((.*)\)(.*?$)/
          token = query[index] = "#{$1}(#{parse_google_to_sphinx $2})#{$3}"
        end       
        
        # translate to sphinx-language
        case token
          when "OR"
            query[index] = "|"
          when "NOT"
            query[index] = "-#{query[index+1]}"
            query[index+1] = ""
          when "AND"
            query[index] = ""
          when /:/
            query[query.size] = "@" + query[index].sub(":", " ")
            query[index] = ""
        end
        
        # remove some spaces
        query[index].gsub!(/^"\s+|\s+"$/, '"')
        
      end
      query.join(" ").squeeze(" ").strip
    end
  
    def reify_results(sphinx_ids)
  
      # order by position and then toss the rest of the data
      # make sure you are using the bundled Sphinx client, which has a patch
      sphinx_ids = sphinx_ids.sort_by do |key, value| 
        value['index'] or raise ConfigurationError, "Your Sphinx client is not properly patched."
      end.map(&:first)
  
      # inverse-modulus map the sphinx ids to the table-specific ids
      ids = Hash.new([])
      sphinx_ids.each do |id|
        ids[MODELS_TO_IDS.invert[id % MODELS_TO_IDS.size]] += [id / MODELS_TO_IDS.size] # yay math
      end
      raise Sphinx::SphinxResponseError, "impossible document id in query result" unless ids.values.flatten.size == sphinx_ids.size
  
      # fetch them for real
      results = []
      ids.each do |model, id_set|
        klass = model.constantize
        finder = klass.respond_to?(:get_cache) ? :get_cache : :find
        logger.debug "** ultrasphinx: using #{klass.name}\##{finder} as finder method"
  
        begin
          results += case instances = id_set.map {|id| klass.send(finder, id)} # XXX temporary until we update cache_fu
            when Hash
              instances.values
            when Array
              instances
            else
              Array(instances)
          end
        rescue ActiveRecord:: ActiveRecordError => e
          raise Sphinx::SphinxResponseError, e.inspect
        end
      end
  
      # put them back in order
      results.sort_by do |r| 
        raise Sphinx::SphinxResponseError, "Bogus ActiveRecord id for #{r.class}:#{r.id}" unless r.id
        index = (sphinx_ids.index(sphinx_id = r.id * MODELS_TO_IDS.size + MODELS_TO_IDS[r.class.base_class.name]))
        raise Sphinx::SphinxResponseError, "Bogus reverse id for #{r.class}:#{r.id} (Sphinx:#{sphinx_id})" unless index
        index / sphinx_ids.size.to_f
      end
      
      # add an accessor for absolute search rank for each record
      results.each_with_index do |r, index|
        i = per_page * current_page + index
        r._metaclass.send(:define_method, "result_index") { i }
      end
      
    end  
    
    # Delegates enumerable methods to @results, if possible. This allows us to behave directly like a WillPaginate::Collection.
    def method_missing(*args)
      if @results.respond_to? args.first
        @results.send(*args)
      else
        super
      end
    end
  
    def logger
      RAILS_DEFAULT_LOGGER
    end
    
  end
end
