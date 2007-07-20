
# Ultrasphinx command-pattern search model

module Ultrasphinx
  class Search
    unloadable if RAILS_ENV == "development"
  
    OPTIONS = {:command => {:search => 0, :excerpt => 1},
      #   :status => {:ok => 0, :error => 1, :retry => 2},
      :search_mode => {:all => 0, :any => 1, :phrase => 2, :boolean => 3, :extended => 4},
      :sort_mode => {:relevance => 0, :desc => 1, :asc => 2, :time => 3},
      :attribute_type => {:integer => 1, :date => 2},
    :group_by => {:day => 0, :week => 1, :month => 2, :year => 3, :attribute => 4}}
  
    DEFAULTS = {:page => 1,
      :models => nil,
      :per_page => 20,
      :sort_by => 'created_at',
      :sort_mode => :relevance,
      :weights => nil,
      :search_mode => :extended,
    :raw_filters => {}}
  
  
    VIEW_OPTIONS = { # XXX this is crappy
      :search_mode => {"all words" => "all", "some words" => "any", "exact phrase" => "phrase", "boolean" => "boolean", "extended" => "extended"}.sort,
    :sort_mode => [["newest first", "desc"], ["oldest first", "asc"], ["relevance", "relevance"]]
    } #, "Time" => :time }
    
    MAX_RETRIES = 4
  
    MODELS = begin
      Hash[*open(CONF_PATH).readlines.select{|s| s =~ /^(source \w|sql_query )/}.in_groups_of(2).map{|model, _id| [model[/source ([\w\d_-]*)/, 1].classify, _id[/(\d*) AS class_id/, 1].to_i]}.flatten] # XXX blargh
    rescue
      puts "Ultrasphinx configuration file not found for #{ENV['RAILS_ENV'].inspect} environment"
      {}
    end
  
    MAX_MATCHES = DAEMON_SETTINGS["max_matches"].to_i
  
    QUERY_TYPES = [:sphinx, :google]
  
    #INDEXES = YAML.load_file(MODELS_HASH).keys.select{|x| !x.blank?}.map(&:tableize) + ["complete"]
  
    attr_reader :options
    attr_reader :query
    attr_reader :results
    attr_reader :response
    attr_reader :subtotals
  
    def self.find *args
      args.push({}) unless args.last.is_a? Hash
      args.unshift :sphinx if args.size == 2
      self.new(*args).run
    end
  
    def initialize style, query, opts={}
      opts = {} unless opts
      raise Sphinx::SphinxArgumentError, "Invalid query type: #{style.inspect}" unless QUERY_TYPES.include? style
      @query = (query || "")
      @parsed_query = style == :google ? parse_google(@query) : @query
  
      @results = []
      @subtotals = {}
      @response = {}
  
      @options = DEFAULTS.merge(Hash[*opts.map do |key, value|
        [key.to_sym,
          if value.respond_to?(:to_i) && value.to_i.to_s == value
            value.to_i
          elsif value == ""
            nil
          elsif value.is_a? String and key.to_s != "sort_by"
            value.to_sym
          else
            value
          end]
        end._flatten_once])
        @options[:models] = Array(@options[:models])
  
        raise Sphinx::SphinxArgumentError, "Invalid options: #{@extra * ', '}" if (@extra = (@options.keys - (OPTIONS.merge(DEFAULTS).keys))).size > 0
      end
  
      def run(instantiate = true)
        # set all the options
        @request = Sphinx::Client.new
        @request.SetServer(PLUGIN_SETTINGS['server_host'], PLUGIN_SETTINGS['server_port'])
        offset, limit = options[:per_page] * (options[:page] - 1), options[:per_page]
        @request.SetLimits offset, limit, [offset + limit, MAX_MATCHES].min
        @request.SetMatchMode map_option(:search_mode)
        @request.SetSortMode map_option(:sort_mode), options[:sort_by]      
  
        if weights = options[:weights]
          @request.SetWeights(Fields.instance.select{|n,t| t == 'text'}.map(&:first).sort.inject([]) do |array, field|
            array << (weights[field] || 1.0)
          end)
        end
  
        #@request.SetIdRange # never useful
  
        unless options[:models].compact.empty?
          @request.SetFilter 'class_id', options[:models].map{|m| MODELS[m.to_s]}
        end        
  
        options[:raw_filters].each do |field, value|
          begin
            unless value.is_a? Range
              @request.SetFilter field, Array(value)
            else
              min, max = [value.first, value.last].map do |x|
                x._to_numeric if x.is_a? String
              end
              unless min.class != max.class
                min, max = max, min if min > max
                @request.SetFilterRange field, min, max
              end
            end
          rescue NoMethodError => e
            raise Sphinx::SphinxArgumentError, "filter: #{field.inspect}:#{value.inspect} is invalid"
          end
        end
        # @request.SetGroup # not useful
  
        tries = 0
        logger.info "Ultrasphinx: Searching for #{query.inspect} (parsed as #{@parsed_query.inspect}), options #{@options.inspect}"
        begin
          # run the search
          @response = @request.Query(@parsed_query)
          logger.info "Ultrasphinx: Search returned, error #{@request.GetLastError.inspect}, warning #{@request.GetLastWarning.inspect}, returned #{total}/#{response['total_found']} in #{time} seconds."
  
          # get all the subtotals, XXX should be configurable
          # andrew says there's a better way to do this
          filtered_request = @request.dup
          MODELS.each do |key, value|
            filtered_request.instance_eval { @filters.delete_if {|f| f['attr'] == 'class_id'} }
            filtered_request.SetFilter 'class_id', [value]
            @subtotals[key] = @request.Query(@parsed_query)['total_found']
  #          logger.debug "Ultrasphinx: Found #{subtotals[key]} records for sub-query #{key} (filters: #{filtered_request.instance_variable_get('@filters').inspect})"
          end
  
          @results = instantiate ? reify_results(response['matches']) : response['matches']
      rescue Sphinx::SphinxResponseError, Sphinx::SphinxTemporaryError, Errno::EPIPE => e
        if (tries += 1) <= MAX_RETRIES
          logger.warn "Ultrasphinx: Restarting query (#{tries} attempts already) (#{e})"
          if tries == MAX_RETRIES
            logger.warn "Ultrasphinx: Sleeping..."
            sleep(3) 
          end
          retry
        else
          logger.warn "Ultrasphinx: Query failed"
          raise e
        end
      end
    end
  
    def excerpt
      run unless run?
      return if results.empty?
  
      maps = results.map do |record|
        [record] <<
        [[:title, :name], [:body, :description, :content]].map do |methods|
          methods.detect{|x| record.respond_to? x}
        end
      end
  
      texts = maps.map do |record, methods|
        [record.send(methods[0]), record.send(methods[1])]
      end.flatten.map{|x| x.gsub(/<.*?>|\.\.\.|\342\200\246|\n|\r/, " ").gsub(/http.*?( |$)/, ' ')}
  
      responses = @request.BuildExcerpts(
        texts, 
        "complete", 
        @parsed_query.gsub(/AND|OR|NOT|\@\w+/, ""),
        :before_match => "<strong>", :after_match => "</strong>",
        :chunk_separator => "...",
        :limit => 200,
        :around => 1).in_groups_of(2)
      
      maps.each_with_index do |record_and_methods, i|
        record, methods = record_and_methods
        2.times do |j|
          record._metaclass.send(:define_method, methods[j]) { responses[i][j] }
        end
      end
  
      @results = maps.map(&:first).map(&:freeze)
    end
  
  
    def total
      [response['total_found'], MAX_MATCHES].min
    end
  
    def found
      results.size
    end
  
    def time
      response['time']
    end
  
    def run?
      !response.blank?
    end
  
    def page
      options[:page]
    end
  
    def per_page
      options[:per_page]
    end
  
    def last_page
      (total / per_page) + (total % per_page == 0 ? 0 : 1)
    end
  
    private
  
    def parse_google query
      return unless query
      # alters google-style querystring into sphinx-style
      query = query.gsub(" AND ", " ").scan(/[^"() ]*["(][^")]*[")]|[^"() ]+/) # thanks chris2
      query.each_with_index do |token, index|
            
        if token =~ /^(.*?)\((.*)\)(.*?$)/
          token = query[index] = "#{$1}(#{parse_google $2})#{$3}" # recurse for parens
        end       
        
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
        
      end
      query.join(" ").squeeze(" ")
    end
  
    def reify_results(sphinx_ids)
      sphinx_ids = sphinx_ids.sort_by{|k, v| v['index']}.map(&:first).reverse # sort and then toss the rest of the data
  
      # find associated record ids
      ids = Hash.new([])
      sphinx_ids.each do |_id|
        ids[MODELS.invert[_id % MODELS.size]] += [_id / MODELS.size] # yay math
      end
      raise Sphinx::SphinxResponseError, "impossible document id in query result" unless ids.values.flatten.size == sphinx_ids.size
  
      # fetch them for real
      results = []
      ids.each do |model, id_set|
        klass = model.constantize
        finder = klass.respond_to?(:get_cache) ? :get_cache : :find
        logger.debug "Ultrasphinx: using #{klass.name}\##{finder} as finder method"
  
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
        index = (sphinx_ids.index(sphinx_id = r.id * MODELS.size + MODELS[r.class.base_class.name]))
        raise Sphinx::SphinxResponseError, "Bogus reverse id for #{r.class}:#{r.id} (Sphinx:#{sphinx_id})" unless index
        index / sphinx_ids.size.to_f
      end
    end
  
    def map_option opt
      opt = opt.to_sym
      OPTIONS[opt][options[opt]] or raise Sphinx::SphinxArgumentError, "Invalid option value :#{opt} => #{options[opt]}"
    end
  
    def logger
      RAILS_DEFAULT_LOGGER
    end
  
  end
end
