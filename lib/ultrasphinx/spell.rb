

module Ultrasphinx

=begin rdoc
== Spelling support

In order to spellcheck your user's query, Ultrasphinx bundles a small spelling module. First, make sure Aspell 0.6, an appropriate Aspell dictionary, and the Rubygem 'raspell' are all installed.
  
Then, copy <tt>examples/app.multi</tt> into your Aspell dictionary folder. It allows you to use Sphinx to generate a custom wordlist for your app. Modify it if you don't want to also use the default American English dictionary.
  
Then, to build the custom wordlist, run:  
  rake ultrasphinx:spelling:build    

Now you can see if a query is correctly spelled as so:
  @correction = Ultrasphinx::Spell.correct(@search.query)

If @correction is not nil, go ahead and suggest it to the user. Otherwise, the query was already correct.

=end

  module Spell  
    SP = Aspell.new("app")   
    SP.suggestion_mode = Aspell::NORMAL
    SP.set_option("ignore-case", "true")
    
    def self.correct string
      correction = string.gsub(/[\w\']+/) do |word| 
        unless SP.check(word)
          SP.suggest(word).first
        else
          word
        end
      end
      
      correction if correction != string
    end    
    
  end    
end

