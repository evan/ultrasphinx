
# http://blog.evanweaver.com/articles/2007/03/10/add-gud-spelning-to-ur-railz-app-or-wharever

module Spell
  unloadable rescue nil
  
  # make sure you've put app.multi (from ../examples) in your system's aspell dictionary folder
  # you also must run rake ultrasphinx:spelling:build to construct the custom dictionary
  SP = Aspell.new("app") 

  SP.suggestion_mode = Aspell::NORMAL
  SP.set_option("ignore-case", "true")
  
  def self.correct string
    string.gsub(/[\w\']+/) do |word| 
      unless SP.check(word)
        SP.suggest(word).first
      else
        word
      end
    end
  end
  
end

