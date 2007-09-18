
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
        
        # force extended query mode
        request.SetMatchMode(Sphinx::Client::SPH_MATCH_EXTENDED) 
      
        offset, limit = opts['per_page'] * (opts['page'] - 1), opts['per_page']
        
        request.SetLimits offset, limit, [offset + limit, MAX_MATCHES].min
        request.SetSortMode SPHINX_CLIENT_PARAMS['sort_mode'][opts['sort_mode']], opts['sort_by'].to_s
      
        if weights = opts['weight']
          # order the weights hash according to the field order for sphinx, and set the missing fields to 1.0
          # XXX we shouldn't really have to access Fields.instance from within Ultrasphinx::Search
          request.SetWeights(Fields.instance.types.select{|n,t| t == 'text'}.map(&:first).sort.inject([]) do |array, field|
            array << (weights[field] || 1.0)
          end)
        end
      
        unless opts['class_name'].compact.empty?
          request.SetFilter 'class_id', opts['class_name'].map{|m| MODELS_TO_IDS[m.to_s]}
        end        
      
        # extract ranged raw filters 
        # XXX some of this mangling might not be necessary
        opts['filter'].each do |field, value|
          begin
            case value
              when Fixnum, Float, BigDecimal, NilClass
                request.SetFilter field, Array(value)
              when Range, Array
                value = [value.begin, value.end] if value.is_a? Range
                min, max = [value.first, value.last].map do |x|
                  x._to_numeric if x.is_a? String
                end
                unless min.class != max.class
                  min, max = max, min if min > max
                  request.SetFilterRange field, min, max
                end
              when String
                opts['parsed_query'] << " @#{field} #{value}"
              else
                raise NoMethodError
            end
          rescue NoMethodError => e
            raise Sphinx::SphinxArgumentError, "filter: #{field.inspect}:#{value.inspect} is invalid"
          end
        end
        
        # request.SetIdRange # never useful        
        
        request
      end    
      
      def get_subtotals(original_request, query)
        # XXX need to move this to use the faceting API, I guess
        request = original_request._deep_dup
        request.instance_eval { @filters.delete_if {|f| f['attr'] == 'class_id'} }
        
        facets = get_facets(request, query, 'class_id')
        
        # class_ids don't use the standard faceting scheme
        Hash[*(MODELS_TO_IDS.map do |klass, id|
          [klass, facets[id] || 0]
        end.flatten)]
      end
      
      def get_facets(original_request, query, original_facet)
        request, facet = original_request._deep_dup, original_facet        
        facet += "_facet" if Fields.instance.types[original_facet] == 'text'            
        
        raise UsageError, "Field #{original_facet} does not exist or was not configured for faceting" unless Fields.instance.types[facet]

        # set the facet query parameter and modify per-page setting so we snag all the facets
        request.SetGroupBy(facet, Sphinx::Client::SPH_GROUPBY_ATTR, '@count desc')
        limit = self.class.client_options['max_facets']
        request.SetLimits 0, limit, [limit, MAX_MATCHES].min
        
        # run the query
        matches = request.Query(query)['matches']
                
        # map the facets back to something sane
        facets = {}
        matches.each do |match|
          match = match.last['attrs'] # :(
#          debugger
          raise ResponseError if facets[match['@groupby']]
          facets[match['@groupby']] = match['@count']
        end
                
        # invert crc's, if we have them
        reverse_map_facets(facets, original_facet)
      end
      
      def reverse_map_facets(facets, facet) 
        facets = facets.dup
      
        if Fields.instance.types[facet] == 'text'        
          unless FACET_CACHE[facet]
            # cache the reverse CRC map for the textual facet if it hasn't been done yet
            # XXX pretty nasty            
            Ultrasphinx.say "caching crc reverse map for text facet #{facet}"
            
            Fields.instance.classes[facet].each do |klass|
              # you can only use a facet from your own self right now; no includes allowed
              field = (MODEL_CONFIGURATION[klass.name]['fields'].detect do |field_hash|
                field_hash['as'] == facet
              end)['field']
          
              klass.connection.execute("SELECT #{field} AS value, CRC32(#{field}) AS crc FROM #{klass.table_name} GROUP BY #{field}").each_hash do |hash|
                (FACET_CACHE[facet] ||= {})[hash['crc'].to_i] = hash['value']
              end                            
            end
          end
          
          # apply the map
          facets = Hash[*(facets.map do |crc, value|
            [FACET_CACHE[facet][crc], value]
          end.flatten)]
        end
        
        facets        
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
          
          finder = self.class.client_options['finder_methods'].detect do |method_name|
            klass.respond_to? method_name
          end
          
          logger.debug "** ultrasphinx: using #{klass.name}.#{finder} as finder method"
    
          begin
            # XXX does not use Memcached's multiget
            results += case instances = id_set.map { |id| klass.send(finder, id) }
              when Hash
                instances.values
              when Array
                instances
              else
                Array(instances)
            end
          rescue ActiveRecord::ActiveRecordError => e
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
          i = per_page * (current_page - 1) + index
          r._metaclass.send('define_method', 'result_index') { i }
        end
        
        results        
      end  

      
      def strip_bogus_characters(s)
        # used to remove some garbage before highlighting
        s.gsub(/<.*?>|\.\.\.|\342\200\246|\n|\r/, " ").gsub(/http.*?( |$)/, ' ') if s
      end
      
      def strip_query_commands(s)
        # XXX dumb hack for query commands, since sphinx doesn't intelligently parse the query in excerpt mode
        s.gsub(/AND|OR|NOT|\@\w+/, "")
      end 
    
    end
  end  
end