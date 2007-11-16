
module Ultrasphinx
  class Search
    module Internals

      # These methods are kept stateless to ease debugging
      
      private
      
      def build_request_with_options opts
      
        request = Riddle::Client.new
        request.instance_eval do          
          @server = Ultrasphinx::CLIENT_SETTINGS['server_host']
          @port = Ultrasphinx::CLIENT_SETTINGS['server_port']          
          @match_mode = :extended # Force extended query mode
          @offset = opts['per_page'] * (opts['page'] - 1)
          @limit = opts['per_page']
          @max_matches = [@offset + @limit, MAX_MATCHES].min
        end
          
        # Sorting
        sort_by = opts['sort_by']
        unless sort_by.blank?
          if opts['sort_mode'].to_s == 'relevance'
            # If you're sorting by a field you don't want 'relevance' order
            raise UsageError, "Sort mode 'relevance' is not valid with a sort_by field"
          end
          request.sort_by = sort_by.to_s
        end
        
        if sort_mode = SPHINX_CLIENT_PARAMS['sort_mode'][opts['sort_mode']]
          request.sort_mode = sort_mode
        else
          raise UsageError, "Sort mode #{opts['sort_mode'].inspect} is invalid"
        end        

        # Weighting
        weights = opts['weights']
        if weights.any?
          # Order according to the field order for Sphinx, and set the missing fields to 1.0
          request.weights = (Fields.instance.types.select{|n,t| t == 'text'}.map(&:first).sort.inject([]) do |array, field|
            array << (weights[field] || 1.0)
          end)
        end
        
        # Class names
        unless Array(opts['class_names']).empty?
          request.filters << Riddle::Client::Filter.new(
            'class_id', 
            (opts['class_names'].map do |model| 
              MODELS_TO_IDS[model.to_s] or 
                MODELS_TO_IDS[model.to_s.constantize.base_class.to_s] or 
                raise UsageError, "Invalid class name #{model.inspect}"
            end), 
            false)
        end          

        # Extract raw filters 
        # XXX We should coerce based on the Field values, not on the class
        Array(opts['filters']).each do |field, value|          
          field = field.to_s
          unless Fields.instance.types[field]
            raise UsageError, "field #{field.inspect} is invalid"
          end
          begin
            case value
              when Integer, Float, BigDecimal, NilClass, Array
                # Just bomb the filter in there
                request.filters << Riddle::Client::Filter.new(field, Array(value), false)
              when Range
                # Make sure ranges point in the right direction
                min, max = [value.begin, value.end].map {|x| x._to_numeric }
                raise NoMethodError unless min <=> max and max <=> min
                min, max = max, min if min > max
                request.filters << Riddle::Client::Filter.new(field, min..max, false)
              when String
                # XXX Hack to move text filters into the query
                opts['parsed_query'] << " @#{field} #{value}"
              else
                raise NoMethodError
            end
          rescue NoMethodError => e
            raise UsageError, "filter value #{value.inspect} for field #{field.inspect} is invalid"
          end
        end
        
        request
      end    
      
      def get_subtotals(original_request, query)
        request = original_request._deep_dup
        request.instance_eval { @filters.delete_if {|filter| filter.attribute == 'class_id'} }
        
        facets = get_facets(request, query, 'class_id')
        
        # Not using the standard facet caching here
        Hash[*(MODELS_TO_IDS.map do |klass, id|
          [klass, facets[id] || 0]
        end.flatten)]
      end
      
      def get_facets(original_request, query, original_facet)
        request, facet = original_request._deep_dup, original_facet        
        facet += "_facet" if Fields.instance.types[original_facet] == 'text'            
        
        unless Fields.instance.types[facet]
          if facet == original_facet
            raise UsageError, "Field #{original_facet} does not exist" 
          else
            raise UsageError, "Field #{original_facet} is a text field, but was not configured for text faceting"
          end
        end
        
        # Set the facet query parameter and modify per-page setting so we snag all the facets
        request.instance_eval do
          @group_by = facet
          @group_function = :attr
          @group_clauses = '@count desc'
          @offset = 0
          @limit = Ultrasphinx::Search.client_options['max_facets']
          @max_matches = [@limit, MAX_MATCHES].min
        end
        
        # Run the query
        begin
          matches = request.query(query, UNIFIED_INDEX_NAME)[:matches]
        rescue DaemonError
          raise ConfigurationError, "Index seems out of date. Run 'rake ultrasphinx:index'"
        end
                
        # Map the facets back to something sane
        facets = {}
        matches.each do |match|
          attributes = match[:attributes]
          raise DaemonError if facets[attributes['@groupby']]
          facets[attributes['@groupby']] = attributes['@count']
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
          
          FACET_CACHE[facet] ||= {}
          klass.connection.execute("SELECT #{field} AS value, CRC32(#{field}) AS hash FROM #{klass.table_name} GROUP BY #{field}").each do |value, hash|
            FACET_CACHE[facet][hash.to_i] = value
          end                            
        end
        FACET_CACHE[facet]
      end
      
      # Inverse-modulus map the Sphinx ids to the table-specific ids
      def convert_sphinx_ids(sphinx_ids)    
        sphinx_ids.sort_by do |item| 
          item[:index]
        end.map do |item|
          class_name = MODELS_TO_IDS.invert[item[:doc] % MODELS_TO_IDS.size]
          raise DaemonError, "Impossible Sphinx document id #{item[:doc]} in query result" unless class_name
          [class_name, item[:doc] / MODELS_TO_IDS.size]
        end
      end

      # Fetch them for real
      def reify_results(ids)
        results = []
        
        ids.each do |klass_name, id|
        
          # What class and class method are we using to get the record?
          klass = klass_name.constantize
          finder = Ultrasphinx::Search.client_options['finder_methods'].detect do |method_name|
            klass.respond_to? method_name
          end
          
          # Load it
          begin
            # XXX Does not use Memcached's multiget, or MySQL's, for that matter
            record = klass.send(finder, id)
            raise ActiveRecord::RecordNotFound unless record
          rescue ActiveRecord::RecordNotFound => e
            if Ultrasphinx::Search.client_options['ignore_missing_records']
              # XXX Should maybe adjust the total_found count, etc
            else
              raise(e)
            end
          end  
          
          # Add it to the list. Cache_fu does funny things with returned record organization.
          results += record.is_a?(Hash) ? record.values : Array(record)                
        end
    
        # Add an accessor for absolute search rank for each record (does anyone use this?)
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
            Riddle::VersionError,
            Riddle::ResponseError,
            Errno::ECONNREFUSED, 
            Errno::ECONNRESET, 
            Errno::EPIPE => e
          tries += 1
          if tries <= Ultrasphinx::Search.client_options['max_retries']
            say "restarting query (#{tries} attempts already) (#{e})"            
            sleep(Ultrasphinx::Search.client_options['retry_sleep_time']) 
            retry
          else
            say "query failed"
            raise DaemonError, e.to_s
          end
        end
      end
      
      def strip_bogus_characters(s)
        # Used to remove some garbage before highlighting
        s.gsub(/<.*?>|\.\.\.|\342\200\246|\n|\r/, " ").gsub(/http.*?( |$)/, ' ') if s
      end
      
      def strip_query_commands(s)
        # XXX Hack for query commands, since Sphinx doesn't intelligently parse the query in excerpt mode
        # Also removes apostrophes in the middle of words so that they don't get split in two.
        s.gsub(/(^|\s)(AND|OR|NOT|\@\w+)(\s|$)/i, "").gsub(/(\w)\'(\w)/, '\1\2')
      end 
    
    end
  end  
end