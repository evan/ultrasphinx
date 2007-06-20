
# Ultrasphinx search model

require 'ultrasphinx'
require 'timeout'
require 'chronic'

class Search
  include Reloadable if ENV['RAILS_ENV'] == "development" and ENV["USER"] == "eweaver"

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
    :sort_mode => :desc,
    :weights => nil,
    :search_mode => :all,
    :belongs_to => nil,
  :raw_filters => {}}

  VIEW_OPTIONS = {
    :search_mode => {"All words" => "all", "Some words" => "any", "Exact phrase" => "phrase", "Boolean" => "boolean"}.sort,
  :sort_mode => {"By relevance" => "relevance", "Descending" => "desc", "Ascending" => "asc"}.sort} #, "Time" => :time }

  MODELS = begin
    Hash[*open(Ultrasphinx::SPHINX_CONF).readlines.select{|s| s =~ /^(source \w|sql_query )/}.in_groups_of(2).map{|model, _id| [model[/source ([\w\d_-]*)/, 1].classify, _id[/(\d*) AS class_id/, 1].to_i]}.flatten] # XXX blargh
  rescue
    puts "Ultrasphinx configuration file not found for #{ENV['RAILS_ENV'].inspect} environment"
    {}
  end

  MAX_MATCHES = Ultrasphinx::DAEMON_CONF["max_matches"].to_i

  QUERY_TYPES = [:sphinx, :google]

  #INDEXES = YAML.load_file(Ultrasphinx::MODELS_CONF).keys.select{|x| !x.blank?}.map(&:tableize) + ["complete"]

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
    raise Ultrasphinx::ParameterError, "Invalid query type: #{style.inspect}" unless QUERY_TYPES.include? style
    query = parse_google(query) if style == :google
    @query = query || ""
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

      raise Ultrasphinx::ParameterError, "Invalid options: #{@extra * ', '}" if (@extra = (@options.keys - (OPTIONS.merge(DEFAULTS).keys))).size > 0
      @options[:belongs_to] = @options[:belongs_to].name if @options[:belongs_to].is_a? Class
    end

    def run(instantiate = true)
      # set all the options
      @request = Sphinx::Client.new
      @request.SetServer(Ultrasphinx::PLUGIN_CONF['server_host'], Ultrasphinx::PLUGIN_CONF['server_port'])
      offset, limit = options[:per_page] * (options[:page] - 1), options[:per_page]
      @request.SetLimits offset, limit, [offset + limit, MAX_MATCHES].min
      @request.SetMatchMode map_option(:search_mode)
      @request.SetSortMode map_option(:sort_mode), options[:sort_by]      
      if weights = options[:weights]
#        breakpoint
        @request.SetWeights((Ultrasphinx::FIELDS.keys - ["id"]).sort.inject([]) do |array, field|
          array << (weights[field] || 1.0)
        end)
      end
      #@request.SetIdRange # never useful
      unless options[:models].compact.empty?
        @request.SetFilter 'class_id', options[:models].map{|m| MODELS[m.to_s]}
      end
      if options[:belongs_to]
        raise Ultrasphinx::ParameterError, "You must specify a specific :model when using :belongs_to" unless options[:models] and options(:models).size == 1
        parent = options[:belongs_to]
        association = parent.class.reflect_on_all_associations.select{|a| options[:models] == a.klass.name}.first
        if MODELS.keys.inject(true) {|b, klass| b and klass.constantize.columns.map(&:name).include? association.options[:foreign_key]}
          key_name = "global_#{association.options[:foreign_key]}"
        else
          key_name = "#{options[:models].first.tableize}_#{association.options[:foreign_key]}"
        end
        @request.SetFilter key_name, [parent.id]
      end
      options[:raw_filters].each do |field, value|
        unless value.is_a? Range
          @request.SetFilter field, Array(value)
        else
          min, max = [value.first, value.last].map do |x|
            x._to_numeric if x.is_a? String
          end
        end
        unless min.class != max.class
          min, max = max, min if min > max
          @request.SetFilterRange field, min, max
        end
      end
      # @request.SetGroup # not useful

      begin
        # run the search
        @response = @request.Query(@query)
        logger.debug "Ultrasphinx: Searched for #{query.inspect}, options #{@options.inspect}, error #{@request.GetLastError.inspect}, warning #{@request.GetLastWarning.inspect}, returned #{total}/#{response['total_found']} in #{time} seconds."

        # get all the subtotals, XXX should be configurable
        _request = @request.dup
        MODELS.each do |key, value|
          _request.instance_eval { @filters.delete_if {|f| f['attr'] == 'class_id'} }
          _request.SetFilter 'class_id', [value]
          @subtotals[key] = @request.Query(@query)['total_found']
          logger.debug "Ultrasphinx: Found #{subtotals[key]} records for sub-query #{key} (filters: #{_request.instance_variable_get('@filters').inspect})"
        end

        @results = instantiate ? reify_results(response['matches']) : response['matches']
    rescue Object => e
      if e.is_a? Sphinx::SphinxInternalError and e.to_s == "searchd error: 112"
        e = Sphinx::SphinxInternalError.new("searchd error: 112. This is a request error. You did something wrong. Sorry; I don't have any more details.")
      end
      raise e #if Rails.development?
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
    end.flatten.map{|x| x.gsub(/<.*?>|\.\.\.|\342\200\246|\n|\r/, " ")}

    begin
      responses = @request.BuildExcerpts(texts, "complete", query,
      :before_match => "<strong>", :after_match => "</strong>",
      :chunk_separator => "...",
      :limit => 200,
      :around => 1).in_groups_of(2)
    rescue Object => e
#      e = Ultrasphinx::CoreError.convert(e) unless e.is_a? Ultrasphinx::Exception
#      logger.warn "Ultrasphinx: searchd excerpt error, #{e.inspect}"
      raise e #if Rails.development?
    end

    maps.each_with_index do |record_and_methods, i|
      record, methods = record_and_methods
      2.times do |j|
        record._metaclass.send(:define_method, methods[j]) { responses[i][j] }
      end
    end

    @results = maps.map(&:first).map(&:freeze)
  end


  def total
#    require 'ruby-debug'; Debugger.start; debugger
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

  #  def parse_google query
  #    # alters google-style querystring into sphinx-style query + options
  #    [query, {}]
  #  end

  def reify_results(sphinx_ids)
    sphinx_ids = sphinx_ids.keys # just toss the index data

    # find associated record ids
    ids = Hash.new([])
    sphinx_ids.each do |_id|
      #      require 'ruby-debug'; Debugger.start; debugger
      ids[MODELS.invert[_id % MODELS.size]] += [_id / MODELS.size] # yay math
    end
    raise Ultrasphinx::ResponseError, "impossible document id in query result" unless ids.values.flatten.size == sphinx_ids.size

    # fetch them for real
    results = []
    ids.each do |model, id_set|
      klass = model.constantize
      finder = klass.respond_to?(:get_cache) ? :get_cache : :find
      logger.debug "Ultrasphinx: using #{klass.name}\##{finder} as finder method"

      begin
        results += case instances = klass.send(finder, id_set)
          when Hash
            instances.values
          when Array
            instances
          else
            Array(instances)
        end
      rescue ActiveRecord:: ActiveRecordError => e
        raise Ultrasphinx::ResponseError, e.inspect
      end
    end

    # put them back in order
    results.sort_by{|r| (sphinx_ids.index((r.id*MODELS.size)+MODELS[r.class.base_class.name])) / sphinx_ids.size.to_f }
  end

  def map_option opt
    opt = opt.to_sym
    OPTIONS[opt][options[opt]] or raise Ultrasphinx::ParameterError, "Invalid option value :#{opt} => #{options[opt]}"
  end

  def logger; ActiveRecord::Base.logger; end

end

class Array
  def _flatten_once
    self.inject([]){|r, el| r + Array(el)}
  end
end

class Object
  def _metaclass; (class << self; self; end); end
end

class String
  def _to_numeric
    zeroless = self.squeeze(" ").strip.sub(/^0+(\d)/, '\1')
    zeroless.sub!(/(\...*?)0+$/, '\1')
    if zeroless.to_i.to_s == zeroless
      zeroless.to_i
    elsif zeroless.to_f.to_s == zeroless
      zeroless.to_f
    elsif date = Chronic.parse(self)
      date.to_i
    else
      self
    end
  end
end

# leftovers

#  blargh
#      Array(options[:belongs_to)).each do |parent| # XXX really, only use one parent right now
#        associations = parent.class.reflect_on_all_associations.select{|a| MODELS.keys.include? a.klass.name}.select{|a| [:has_many, :has_one].include? a.macro}.select{|a| !a.options[:through]} # no has_many :through right now
#        names = associations.map(&:klass).map(&:name)
#        if names.size > 1 and !options[:models) and names.size < MODELS.size # XXX may return spurious results right now
#          associations.each {|a| SetFilter "#{a.klass.name.tableize}_#{a.options[:foreign_key]}", [parent.id, Ultrasphinx::MAX_INT]}
#          SetFilter 'class_id', MODELS.values_at(*names)
#        elsif options[:models) or names.size == 1
#
#        else
#          associations.each {|a| SetFilter "#{a.klass.name.tableize}_#{a.options[:foreign_key]}", [parent.id, Ultrasphinx::MAX_INT]}
