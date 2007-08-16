
module Ultrasphinx
  class Search
    module Internals

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
          # XXX we shouldn't really have to access Fields.instance from within Ultrasphinx::Search
          request.SetWeights(Fields.instance.select{|n,t| t == 'text'}.map(&:first).sort.inject([]) do |array, field|
            array << (weights[field] || 1.0)
          end)
        end
      
        unless opts[:models].compact.empty?
          request.SetFilter 'class_id', opts[:models].map{|m| MODELS_TO_IDS[m.to_s]}
        end        
      
        # extract ranged raw filters 
        # XXX some of this mangling might not be necessary
        opts[:filters].each do |field, value|
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