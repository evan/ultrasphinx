
module Ultrasphinx
  class Search
    module Parser
      
      class Error < RuntimeError; end

      OPERATORS = {
        'OR' => '|',
        'AND' => '',
        'NOT' => '-',
        'or' => '|',
        'and' => '',
        'not' => '-'
      }
            
      private
      
      def parse query
        # Alters a Google query string into Sphinx 0.97 style
        return "" if query.blank?
        # Parse
        token_hash = token_stream_to_hash(query_to_token_stream(query))  
        # Join everything up and remove some spaces
        token_hash_to_array(token_hash).join(" ").squeeze(" ").strip
      end
      

      def token_hash_to_array(token_hash)              
        query = []
        
        token_hash.sort_by do |key, value| 
          key or ""
        end.each do |field, contents|
          # first operator always goes outside
          query << contents.first.first 
          
          query << "@#{field}" if field
          query << "(" if field and contents.size > 1
          
          contents.each_with_index do |op_and_content, index|
            op, content = op_and_content
            query << op unless index == 0
            query << content
          end
          
          query << ")" if field and contents.size > 1        
        end
        
        # XXX swap the first pair if the order is reversed
        if [OPERATORS['NOT'], OPERATORS['OR']].include? query.first.upcase
          query[0], query[1] = query[1], query[0]
        end
        
        query
      end
      

      def query_to_token_stream(query)      
        # First, split query on spaces that are not inside sets of quotes or parens
        query = query.to_s.scan(/[^"() ]*["(][^")]*[")]|[^"() ]+/) 
      
        token_stream = []
        has_operator = false
        
        query.each_with_index do |subtoken, index|
      
          # recurse for parens, if necessary
          if subtoken =~ /^(.*?)\((.*)\)(.*?$)/
            subtoken = query[index] = "#{$1}(#{parse $2})#{$3}"
          end       
          
          # add to the stream, converting the operator
          if !has_operator
            if OPERATORS.to_a.flatten.include? subtoken and index != (query.size - 1) # operators at the end of the string are not parsed
              token_stream << OPERATORS[subtoken] || subtoken
              has_operator = true # flip
            else
              token_stream << ""
              token_stream << subtoken
            end
          else
            if OPERATORS.to_a.flatten.include? subtoken
              # drop extra operator
            else
              token_stream << subtoken
              has_operator = false # flop
            end
          end        
        end
        
        raise Error, "#{token_stream.inspect} is not a valid token stream" unless token_stream.size % 2 == 0        
        token_stream.in_groups_of(2) 
      end
      
      
      def token_stream_to_hash(token_stream)
        token_hash = Hash.new([])        
        token_stream.map do |operator, content|
          # remove some spaces
          content.gsub!(/^"\s+|\s+"$/, '"')
          # convert fields into sphinx style, reformat the stream object
          if content =~ /(.*?):(.*)/
            token_hash[$1] += [[operator, $2]]
          else
            token_hash[nil] += [[operator, content]]
          end        
        end
        token_hash
      end


    end
  end
end