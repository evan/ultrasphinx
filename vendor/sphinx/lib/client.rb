# = client.rb - Sphinx Client API
# 
# Author::    Dmytro Shteflyuk <mailto:kpumuk@kpumuk.info>.
# Copyright:: Copyright (c) 2006 - 2007 Dmytro Shteflyuk
# License::   Distributes under the same terms as Ruby
# Version::   0.3.0
# Website::   http://kpumuk.info/projects/ror-plugins/sphinx
#
# This library is distributed under the terms of the Ruby license.
# You can freely distribute/modify this library.

# ==Sphinx Client API
# 
# The Sphinx Client API is used to communicate with <tt>searchd</tt>
# daemon and get search results from Sphinx.
# 
# ===Usage
# 
#   sphinx = Sphinx::Client.new
#   result = sphinx.Query('test')
#   ids = result['matches'].map { |id, value| id }.join(',')
#   posts = Post.find :all, :conditions => "id IN (#{ids})"
#   
#   docs = posts.map(&:body)
#   excerpts = sphinx.BuildExcerpts(docs, 'index', 'test')
module Sphinx
  # :stopdoc:

  class SphinxError < StandardError; end
  class SphinxArgumentError < SphinxError; end
  class SphinxConnectError < SphinxError; end
  class SphinxResponseError < SphinxError; end
  class SphinxInternalError < SphinxError; end
  class SphinxTemporaryError < SphinxError; end
  class SphinxUnknownError < SphinxError; end

  # :startdoc:

  class Client
  
    # :stopdoc:
  
    # Known searchd commands
  
    # search command
    SEARCHD_COMMAND_SEARCH  = 0
    # excerpt command
    SEARCHD_COMMAND_EXCERPT = 1
    # update command
    SEARCHD_COMMAND_UPDATE  = 2 
  
    # Current client-side command implementation versions
    
    # search command version
    VER_COMMAND_SEARCH  = 0x107
    # excerpt command version
    VER_COMMAND_EXCERPT = 0x100
    # update command version
    VER_COMMAND_UPDATE  = 0x100
    
    # Known searchd status codes
  
    # general success, command-specific reply follows
    SEARCHD_OK      = 0
    # general failure, command-specific reply may follow
    SEARCHD_ERROR   = 1
    # temporaty failure, client should retry later
    SEARCHD_RETRY   = 2
    # general success, warning message and command-specific reply follow 
    SEARCHD_WARNING = 3    
    
    # :startdoc:
  
    # Known match modes
  
    # match all query words
    SPH_MATCH_ALL      = 0 
    # match any query word
    SPH_MATCH_ANY      = 1 
    # match this exact phrase
    SPH_MATCH_PHRASE   = 2 
    # match this boolean query
    SPH_MATCH_BOOLEAN  = 3 
    # match this extended query
    SPH_MATCH_EXTENDED = 4 
    
    # Known sort modes
  
    # sort by document relevance desc, then by date
    SPH_SORT_RELEVANCE     = 0
    # sort by document date desc, then by relevance desc
    SPH_SORT_ATTR_DESC     = 1
    # sort by document date asc, then by relevance desc
    SPH_SORT_ATTR_ASC      = 2
    # sort by time segments (hour/day/week/etc) desc, then by relevance desc
    SPH_SORT_TIME_SEGMENTS = 3
    # sort by SQL-like expression (eg. "@relevance DESC, price ASC, @id DESC")
    SPH_SORT_EXTENDED      = 4
    
    # Known attribute types
  
    # this attr is just an integer
    SPH_ATTR_INTEGER   = 1
    # this attr is a timestamp
    SPH_ATTR_TIMESTAMP = 2 
    
    # Known grouping functions
  
    # group by day
    SPH_GROUPBY_DAY   = 0
    # group by week
    SPH_GROUPBY_WEEK  = 1 
    # group by month
    SPH_GROUPBY_MONTH = 2 
    # group by year
    SPH_GROUPBY_YEAR  = 3
    # group by attribute value
    SPH_GROUPBY_ATTR  = 4
    
    # Constructs the <tt>Sphinx::Client</tt> object and sets options to their default values. 
    def initialize
      @host       = 'localhost'         # searchd host (default is "localhost")
      @port       = 3312                # searchd port (default is 3312)
      @offset     = 0                   # how many records to seek from result-set start (default is 0)
      @limit      = 20                  # how many records to return from result-set starting at offset (default is 20)
      @mode       = SPH_MATCH_ALL       # query matching mode (default is SPH_MATCH_ALL)
      @weights    = []                  # per-field weights (default is 1 for all fields)
      @sort       = SPH_SORT_RELEVANCE  # match sorting mode (default is SPH_SORT_RELEVANCE)
      @sortby     = ''                  # attribute to sort by (defualt is "")
      @min_id     = 0                   # min ID to match (default is 0)
      @max_id     = 0xFFFFFFFF          # max ID to match (default is UINT_MAX)
      @filters    = []                  # search filters
      @groupby    = ''                  # group-by attribute name
      @groupfunc  = SPH_GROUPBY_DAY     # function to pre-process group-by attribute value with
      @groupsort  = '@group desc'       # group-by sorting clause (to sort groups in result set with)
      @maxmatches = 1000                # max matches to retrieve
    
      @error      = ''                  # last error message
      @warning    = ''                  # last warning message
    end
  
    # Get last error message.
    def GetLastError
      @error
    end
    
    # Get last warning message.
    def GetLastWarning
      @warning
    end
    
    # Set searchd server.
    def SetServer(host, port)
      assert { host.instance_of? String }
      assert { port.instance_of? Fixnum }

      @host = host
      @port = port
    end
   
    # Set match offset, count, and max number to retrieve.
    def SetLimits(offset, limit, max = 0)
      assert { offset.instance_of? Fixnum }
      assert { limit.instance_of? Fixnum }
      assert { max.instance_of? Fixnum }
      assert { offset >= 0 }
      assert { limit > 0 }
      assert { max >= 0 }

      @offset = offset
      @limit = limit
      @maxmatches = max if max > 0
    end
    
    # Set match mode.
    def SetMatchMode(mode)
      assert { mode == SPH_MATCH_ALL \
            || mode == SPH_MATCH_ANY \
            || mode == SPH_MATCH_PHRASE \
            || mode == SPH_MATCH_BOOLEAN \
            || mode == SPH_MATCH_EXTENDED }

      @mode = mode
    end
    
    # Set matches sorting mode.
    def SetSortMode(mode, sortby = '')
      assert { mode == SPH_SORT_RELEVANCE \
            || mode == SPH_SORT_ATTR_DESC \
            || mode == SPH_SORT_ATTR_ASC \
            || mode == SPH_SORT_TIME_SEGMENTS \
            || mode == SPH_SORT_EXTENDED }
      assert { sortby.instance_of? String }
      assert { mode == SPH_SORT_RELEVANCE || !sortby.empty? }

      @sort = mode
      @sortby = sortby
    end
    
    # Set per-field weights.
    def SetWeights(weights)
      assert { weights.instance_of? Array }
      weights.each do |weight|
        assert { weight.instance_of? Fixnum }
      end

      @weights = weights
    end
    
    # Set IDs range to match.
    # 
    # Only match those records where document ID is beetwen <tt>min_id</tt> and <tt>max_id</tt> 
    # (including <tt>min_id</tt> and <tt>max_id</tt>).
    def SetIDRange(min, max)
      assert { min.instance_of? Fixnum }
      assert { max.instance_of? Fixnum }
      assert { min <= max }

      @min_id = min
      @max_id = max
    end
    
    # Set values filter.
    # 
    # Only match those records where <tt>attribute</tt> column values
    # are in specified set.
    def SetFilter(attribute, values, exclude = false)
      assert { attribute.instance_of? String }
      assert { values.instance_of? Array }
      assert { !values.empty? }

      if values.instance_of?(Array) && values.size > 0
        values.each do |value|
          assert { value.instance_of? Fixnum }
        end
      
        @filters << { 'attr' => attribute, 'exclude' => exclude, 'values' => values }
      end
    end
    
    # Set range filter.
    # 
    # Only match those records where <tt>attribute</tt> column value
    # is beetwen <tt>min</tt> and <tt>max</tt> (including <tt>min</tt> and <tt>max</tt>).
    def SetFilterRange(attribute, min, max, exclude = false)
      assert { attribute.instance_of? String }
      assert { min.instance_of? Fixnum }
      assert { max.instance_of? Fixnum }
      assert { min <= max }
    
      @filters << { 'attr' => attribute, 'exclude' => exclude, 'min' => min, 'max' => max }
    end
    
    # Set grouping attribute and function.
    #
    # In grouping mode, all matches are assigned to different groups
    # based on grouping function value.
    #
    # Each group keeps track of the total match count, and the best match
    # (in this group) according to current sorting function.
    #
    # The final result set contains one best match per group, with
    # grouping function value and matches count attached.
    #
	# Groups in result set could be sorted by any sorting clause,
	# including both document attributes and the following special
	# internal Sphinx attributes:
	#
	# * @id - match document ID;
	# * @weight, @rank, @relevance -  match weight;
	# * @group - groupby function value;
	# * @count - amount of matches in group.
	#
	# the default mode is to sort by groupby value in descending order,
	# ie. by '@group desc'.
	#
	# 'total_found' would contain total amount of matching groups over
	# the whole index.
	#
	# WARNING: grouping is done in fixed memory and thus its results
	# are only approximate; so there might be more groups reported
	# in total_found than actually present. @count might also
	# be underestimated. 
    #
    # For example, if sorting by relevance and grouping by "published"
    # attribute with SPH_GROUPBY_DAY function, then the result set will
    # contain one most relevant match per each day when there were any
    # matches published, with day number and per-day match count attached,
    # and sorted by day number in descending order (ie. recent days first).
    def SetGroupBy(attribute, func, groupsort = '@group desc')
      assert { attribute.instance_of? String }
      assert { groupsort.instance_of? String }
      assert { func == SPH_GROUPBY_DAY \
            || func == SPH_GROUPBY_WEEK \
            || func == SPH_GROUPBY_MONTH \
            || func == SPH_GROUPBY_YEAR \
            || func == SPH_GROUPBY_ATTR }

      @groupby = attribute
      @groupfunc = func
      @groupsort = groupsort
    end
    
    # Connect to searchd server and run given search query.
    #
    # * <tt>query</tt> -- query string
    # * <tt>index</tt> -- index name to query, default is "*" which means to query all indexes
    #
    # returns hash which has the following keys on success:
    # 
    # * <tt>'matches'</tt> -- hash which maps found document_id to ('weight', 'group') hash
    # * <tt>'total'</tt> -- total amount of matches retrieved (upto SPH_MAX_MATCHES, see sphinx.h)
    # * <tt>'total_found'</tt> -- total amount of matching documents in index
    # * <tt>'time'</tt> -- search time
    # * <tt>'words'</tt> -- hash which maps query terms (stemmed!) to ('docs', 'hits') hash
    def Query(query, index = '*')
      sock = self.Connect
      
      # build request
  
      # mode and limits
      req = [@offset, @limit, @mode, @sort].pack('NNNN')
      req << [@sortby.length].pack('N') + @sortby
      # query itself
      req << [query.length].pack('N') + query
      # weights
      req << [@weights.length].pack('N')
      req << @weights.pack('N' * @weights.length)
      # indexes
      req << [index.length].pack('N') + index
      # id range
      req << [@min_id.to_i, @max_id.to_i].pack('NN')
      
      # filters
      req << [@filters.length].pack('N')
      @filters.each do |filter|
        req << [filter['attr'].length].pack('N') + filter['attr']

        unless filter['values'].nil?
          req << [filter['values'].length].pack('N')
          req << filter['values'].pack('N' * filter['values'].length)
        else
          req << [0, filter['min'], filter['max']].pack('NNN')
        end
        req << [filter['exclude'] ? 1 : 0].pack('N')
      end
      
      # group-by, max matches, sort-by-group flag
      req << [@groupfunc, @groupby.length].pack('NN') + @groupby
      req << [@maxmatches].pack('N')
      req << [@groupsort.length].pack('N') + @groupsort
      
      # send query, get response
      len = req.length
      # add header
      req = [SEARCHD_COMMAND_SEARCH, VER_COMMAND_SEARCH, len].pack('nnN') + req
      sock.send(req, 0)
      
      response = GetResponse(sock, VER_COMMAND_SEARCH)
      
      # parse response
      result = {}
      max = response.length # protection from broken response
  
      # read schema
      p = 0
      fields = []
      attrs = {}
      attrs_names_in_order = []
      
      nfields = response[p, 4].unpack('N*').first; p += 4
      while nfields > 0 and p < max
        nfields -= 1
        len = response[p, 4].unpack('N*').first; p += 4
        fields << response[p, len]; p += len
      end
      result['fields'] = fields
  
      nattrs = response[p, 4].unpack('N*').first; p += 4
      while nattrs > 0 && p < max
        nattrs -= 1
        len = response[p, 4].unpack('N*').first; p += 4
        attr = response[p, len]; p += len
        type = response[p, 4].unpack('N*').first; p += 4
        attrs[attr] = type
        attrs_names_in_order << attr
      end
      result['attrs'] = attrs
      
      # read match count
      count = response[p, 4].unpack('N*').first; p += 4
            
      # read matches
      result['matches'], index = {}, 0
      while count > 0 and p < max
        count -= 1
        doc, weight = response[p, 8].unpack('N*N*'); p += 8
  
        result['matches'][doc] ||= {}
        result['matches'][doc]['weight'] = weight
        result['matches'][doc]['index'] = index
        attrs_names_in_order.each do |attr|
          val = response[p, 4].unpack('N*').first; p += 4
          result['matches'][doc]['attrs'] ||= {}
          result['matches'][doc]['attrs'][attr] = val
        end
        index += 1
      end
      result['total'], result['total_found'], msecs, words = response[p, 16].unpack('N*N*N*N*'); p += 16
      result['time'] = '%.3f' % (msecs / 1000.0)
      
      result['words'] = {}
      while words > 0 and p < max
        words -= 1
        len = response[p, 4].unpack('N*').first; p += 4
        word = response[p, len]; p += len
        docs, hits = response[p, 8].unpack('N*N*'); p += 8
        result['words'][word] = { 'docs' => docs, 'hits' => hits }
      end
      
      result
    end
  
    # Connect to searchd server and generate exceprts from given documents.
    #
    # * <tt>docs</tt> -- an array of strings which represent the documents' contents
    # * <tt>index</tt> -- a string specifiying the index which settings will be used
    # for stemming, lexing and case folding
    # * <tt>words</tt> -- a string which contains the words to highlight
    # * <tt>opts</tt> is a hash which contains additional optional highlighting parameters.
    # 
    # You can use following parameters:
    # * <tt>'before_match'</tt> -- a string to insert before a set of matching words, default is "<b>"
    # * <tt>'after_match'</tt> -- a string to insert after a set of matching words, default is "<b>"
    # * <tt>'chunk_separator'</tt> -- a string to insert between excerpts chunks, default is " ... "
    # * <tt>'limit'</tt> -- max excerpt size in symbols (codepoints), default is 256
    # * <tt>'around'</tt> -- how much words to highlight around each match, default is 5
    #
    # Returns an array of string excerpts on success.
    def BuildExcerpts(docs, index, words, opts = {})
      assert { docs.instance_of? Array }
      assert { index.instance_of? String }
      assert { words.instance_of? String }
      assert { opts.instance_of? Hash }

      sock = self.Connect
  
      # fixup options
      opts['before_match'] ||= '<b>';
      opts['after_match'] ||= '</b>';
      opts['chunk_separator'] ||= ' ... ';
      opts['limit'] ||= 256;
      opts['around'] ||= 5;
      
      # build request
      
      # v.1.0 req
      req = [0, 1].pack('N2'); # mode=0, flags=1 (remove spaces)
      # req index
      req << [index.length].pack('N') + index
      # req words
      req << [words.length].pack('N') + words
  
      # options
      req << [opts['before_match'].length].pack('N') + opts['before_match']
      req << [opts['after_match'].length].pack('N') + opts['after_match']
      req << [opts['chunk_separator'].length].pack('N') + opts['chunk_separator']
      req << [opts['limit'].to_i, opts['around'].to_i].pack('NN')
      
      # documents
      req << [docs.size].pack('N');
      docs.each do |doc|
        assert { doc.instance_of? String }

        req << [doc.length].pack('N') + doc
      end
      
      # send query, get response
      len = req.length
      # add header
      req = [SEARCHD_COMMAND_EXCERPT, VER_COMMAND_EXCERPT, len].pack('nnN') + req
      sock.send(req, 0)
      
      response = GetResponse(sock, VER_COMMAND_EXCERPT)
      
      # parse response
      p = 0
      res = []
      rlen = response.length
      docs.each do |doc|
        len = response[p, 4].unpack('N*').first; p += 4
        if p + len > rlen
          @error = 'incomplete reply'
          raise SphinxResponseError, @error
        end
        res << response[p, len]; p += len
      end
      return res
    end
    
	# Attribute updates
    #
	# Update specified attributes on specified documents.
	#
	# * <tt>index</tt> is a name of the index to be updated
	# * <tt>attrs</tt> is an array of attribute name strings.
	# * <tt>values</tt> is a hash where key is document id, and value is an array of
	# new attribute values
	#
	# Returns number of actually updated documents (0 or more) on success.
	# Returns -1 on failure.
	#
	# Usage example:
	#    sphinx.UpdateAttributes('index', ['group'], { 123 => [456] })
    def UpdateAttributes(index, attrs, values)
      # verify everything
      assert { index.instance_of? String }
      
      assert { attrs.instance_of? Array }
      attrs.each do |attr|
        assert { attr.instance_of? String }
      end
      
      assert { values.instance_of? Hash }
      values.each do |id, entry|
        assert { id.instance_of? Fixnum }
        assert { entry.instance_of? Array }
        assert { entry.length == attrs.length }
        entry.each do |v|
          assert { v.instance_of? Fixnum }
        end
      end
      
      # build request
      req = [index.length].pack('N') + index
      
      req << [attrs.length].pack('N')
      attrs.each do |attr|
        req << [attr.length].pack('N') + attr
      end
      
      req << [values.length].pack('N')
      values.each do |id, entry|
        req << [id].pack('N')
        req << entry.pack('N' * entry.length)
      end
      
      # connect, send query, get response
      sock = self.Connect
      len = req.length
      req = [SEARCHD_COMMAND_UPDATE, VER_COMMAND_UPDATE, len].pack('nnN') + req # add header
      sock.send(req, 0)
      
      response = self.GetResponse(sock, VER_COMMAND_UPDATE)
      
      # parse response
      response[0, 4].unpack('N*').first
    end
  
    protected
    
      # Connect to searchd server.
      def Connect
        begin
          sock = TCPSocket.new(@host, @port)
        rescue
          @error = "connection to #{@host}:#{@port} failed"
          raise SphinxConnectError, @error
        end
        
        v = sock.recv(4).unpack('N*').first
        if v < 1
          sock.close
          @error = "expected searchd protocol version 1+, got version '#{v}'"
          raise SphinxConnectError, @error
        end
        
        sock.send([1].pack('N'), 0)
        sock
      end
      
      # Get and check response packet from searchd server.
      def GetResponse(sock, client_version)
        header = sock.recv(8)
        status, ver, len = header.unpack('n2N')
        response = ''
        left = len
        while left > 0 do
          begin
            chunk = sock.recv(left)
            if chunk
              response << chunk
              left -= chunk.length
            end
          rescue EOFError
            break
          end
        end
        sock.close
    
        # check response
        read = response.length
        if response.empty? or read != len
          @error = len \
            ? "failed to read searchd response (status=#{status}, ver=#{ver}, len=#{len}, read=#{read})" \
            : 'received zero-sized searchd response'
          raise SphinxResponseError, @error
        end
        
        # check status
        if (status == SEARCHD_WARNING)
          wlen = response[0, 4].unpack('N*').first
          @warning = response[4, wlen]
          return response[4 + wlen, response.length - 4 - wlen]
        end

        if status == SEARCHD_ERROR
          @error = 'searchd error: ' + response[4, response.length - 4]
          raise SphinxInternalError, @error
        end
    
        if status == SEARCHD_RETRY
          @error = 'temporary searchd error: ' + response[4, response.length - 4]
          raise SphinxTemporaryError, @error
        end
    
        unless status == SEARCHD_OK
          @error = "unknown status code: '#{status}'"
          raise SphinxUnknownError, @error
        end
        
        # check version
        if ver < client_version
          @warning = "searchd command v.#{ver >> 8}.#{ver & 0xff} older than client's " +
            "v.#{client_version >> 8}.#{client_version & 0xff}, some options might not work"
        end
        
        return response
      end
      
      # :stopdoc:
      def assert
        raise 'Assertion failed!' unless yield if $DEBUG
      end
      # :startdoc:
  end
end