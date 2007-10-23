
module Ultrasphinx
  class Search
    module Internals

      # These methods are kept stateless to ease debugging
      
      private
      
      def build_request_with_options opts
      
        request = Sphinx::Client.new
      
        request.SetServer(
          Ultrasphinx::CLIENT_SETTINGS['server_host'], 
          Ultrasphinx::CLIENT_SETTINGS['server_port']
        )
        
        # Force extended query mode
        request.SetMatchMode(Sphinx::Client::SPH_MATCH_EXTENDED) 
      
        offset, limit = opts['per_page'] * (opts['page'] - 1), opts['per_page']
        
        request.SetLimits offset, limit, [offset + limit, MAX_MATCHES].min
        
        if SPHINX_CLIENT_PARAMS['sort_mode'][opts['sort_mode']]
          request.SetSortMode SPHINX_CLIENT_PARAMS['sort_mode'][opts['sort_mode']], opts['sort_by'].to_s
        else
          raise UsageError, "Sort mode #{opts['sort_mode'].inspect} is invalid"
        end
      
        if weights = opts['weights']
          # Order the weights hash according to the field order for Sphinx, and set the missing fields to 1.0
          request.SetWeights(Fields.instance.types.select{|n,t| t == 'text'}.map(&:first).sort.inject([]) do |array, field|
            array << (weights[field] || 1.0)
          end)
        end

        unless opts['class_names'].compact.empty?
          request.SetFilter('class_id', (opts['class_names'].map do |model| 
            MODELS_TO_IDS[model.to_s] or 
            MODELS_TO_IDS[model.to_s.constantize.base_class.to_s] or 
            raise UsageError, "Invalid class name #{model.inspect}"
          end))
        end
      
        # Extract ranged raw filters 
        # Some of this mangling might not be necessary
        opts['filters'].each do |field, value|          
          field = field.to_s
          unless Fields.instance.types[field]
            raise Sphinx::SphinxArgumentError, "field #{field.inspect} is invalid"
          end
          begin
            case value
              when Fixnum, Float, BigDecimal, NilClass, Array
                request.SetFilter field, Array(value)
              when Range
                min, max = [value.begin, value.end].map do |x|
                  x._to_numeric
                end
                raise NoMethodError unless min <=> max and max <=> min
                min, max = max, min if min > max
                request.SetFilterRange field, min, max
              when String
                opts['parsed_query'] << " @#{field} #{value}"
              else
                raise NoMethodError
            end
          rescue NoMethodError => e
            raise Sphinx::SphinxArgumentError, "filter value #{value.inspect} for field #{field.inspect} is invalid"
          end
        end
        
        request
      end    
      
      def get_subtotals(original_request, query)
        request = original_request._deep_dup
        request.instance_eval { @filters.delete_if {|f| f['attr'] == 'class_id'} }
        
        facets = get_facets(request, query, 'class_id')
        
        # Not using the standard facet caching here
        Hash[*(MODELS_TO_IDS.map do |klass, id|
          [klass, facets[id] || 0]
        end.flatten)]
      end
      
      def get_facets(original_request, query, original_facet)
        request, facet = original_request._deep_dup, original_facet        
        facet += "_facet" if Fields.instance.types[original_facet] == 'text'            
        
        raise UsageError, "Field #{original_facet} does not exist or was not configured for faceting" unless Fields.instance.types[facet]

        # Set the facet query parameter and modify per-page setting so we snag all the facets
        request.SetGroupBy(facet, Sphinx::Client::SPH_GROUPBY_ATTR, '@count desc')
        limit = self.class.client_options['max_facets']
        request.SetLimits 0, limit, [limit, MAX_MATCHES].min
        
        # Run the query
        begin
          matches = request.Query(query)['matches']
        rescue Sphinx::SphinxInternalError
          raise ConfigurationError, "Index is out of date. Run 'rake ultrasphinx:index'"
        end
                
        # Map the facets back to something sane
        facets = {}
        matches.each do |match|
          match = match.last['attrs'] # :(
          raise ResponseError if facets[match['@groupby']]
          facets[match['@groupby']] = match['@count']
        end
                
        # Invert hash's, if we have them
        reverse_map_facets(facets, original_facet)
      end
      
      def reverse_map_facets(facets, facet) 
        facets = facets.dup
      
        if Fields.instance.types[facet] == 'text'        
          # Apply the map, rebuilding if the cache is missing or out-of-date
          facets = Hash[*(facets.map do |hash, value|
            rebuild_facet_cache(facet) unless FACET_CACHE[facet] and FACET_CACHE[facet].has_key?(hash)
            [FACET_CACHE[facet][hash], value]
          end.flatten)]
        end
        
        facets        
      end
      
      def rebuild_facet_cache(facet)
        # Cache the reverse hash map for the textual facet if it hasn't been done yet
        # XXX not necessarily optimal since it requires a direct DB hit once per mongrel
        Ultrasphinx.say "caching hash reverse map for text facet #{facet}"
        
        Fields.instance.classes[facet].each do |klass|
          # you can only use a facet from your own self right now; no includes allowed
          field = MODEL_CONFIGURATION[klass.name]['fields'].detect do |field_hash|
            field_hash['as'] == facet
          end
                    
          raise ConfigurationError, "Model #{klass.name} has the requested '#{facet}' field, but it was not configured for faceting" unless field
          field = field['field']
          
          if hash_stored_procedure = ADAPTER_SQL_FUNCTIONS[ADAPTER]['hash_stored_procedure']
            klass.connection.execute(hash_stored_procedure)
          end
                
          klass.connection.execute("SELECT #{field} AS value, #{ADAPTER_SQL_FUNCTIONS[ADAPTER]['hash']._interpolate(field)} AS hash FROM #{klass.table_name} GROUP BY #{field}").each_hash do |hash|
            (FACET_CACHE[facet] ||= {})[hash['hash'].to_i] = hash['value']
          end                            
        end
        FACET_CACHE[facet]
      end
      
      # Inverse-modulus map the sphinx ids to the table-specific ids
      def convert_sphinx_ids(sphinx_ids)    
        # First order by position and then toss the rest of the data
        sphinx_ids.sort_by do |key, value| 
          value['index']
        end.map do |array|
          array.first
        end.map do |id|
          class_name = MODELS_TO_IDS.invert[id % MODELS_TO_IDS.size]
          raise Sphinx::SphinxResponseError, "Impossible Sphinx id #{id} in query result" unless class_name
          [class_name, id / MODELS_TO_IDS.size]
        end
      end

      # Fetch them for real
      def reify_results(ids)
        results = []
        ids.each do |klass_name, id|
          klass = klass_name.constantize          
          finder = self.class.client_options['finder_methods'].detect do |method_name|
            klass.respond_to? method_name
          end
          
          begin
            # XXX Does not use Memcached's multiget
            instance = klass.send(finder, id)
            results += if instance.is_a?(Hash) 
              instance.values
            else
              Array(instance)
            end
          rescue ActiveRecord::ActiveRecordError => e
            raise Sphinx::SphinxResponseError, e.inspect
          end
        end
    
        # Add an accessor for absolute search rank for each record
        results.each_with_index do |result, index|
          i = per_page * (current_page - 1) + index
          result._metaclass.send('define_method', 'result_index') { i }
        end
        
        results        
      end  
      
      def perform_action_with_retries
        tries = 0
        begin
          yield
        rescue NoMethodError,
            Sphinx::SphinxConnectError, 
            Sphinx::SphinxResponseError, 
            Sphinx::SphinxTemporaryError, 
            Errno::ECONNRESET, 
            Errno::EPIPE => e
          tries += 1
          if tries <= self.class.client_options['max_retries']
            say "restarting query (#{tries} attempts already) (#{e})"            
            sleep(self.class.client_options['retry_sleep_time']) 
            retry
          else
            say "query failed"
            raise Sphinx::SphinxConnectError, e.to_s
          end
        end
      end
      
      def strip_bogus_characters(s)
        # Used to remove some garbage before highlighting
        s.gsub(/<.*?>|\.\.\.|\342\200\246|\n|\r/, " ").gsub(/http.*?( |$)/, ' ') if s
      end
      
      def strip_query_commands(s)
        # XXX Hack for query commands, since sphinx doesn't intelligently parse the query in excerpt mode
        # Also removes apostrophes in the middle of words so that they don't get split in two.
        s.gsub(/(^|\s)(AND|OR|NOT|\@\w+)(\s|$)/i, "").gsub(/(\w)\'(\w)/, '\1\2')
      end 
    
    end
  end  
end