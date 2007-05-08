
# http://blog.evanweaver.com/articles/2007/03/10/add-gud-spelning-to-ur-railz-app-or-wharever

begin
  require 'raspell'

  module Spell
    SP = Aspell.new("app")
    SP.suggestion_mode = Aspell::NORMAL
    SP.set_option("ignore-case", "true")
    
    def self.correct string
       string.gsub(/[\w\']+/) do |word| 
         not SP.check(word) and SP.suggest(word).first or word 
       end
    end
    
  end
rescue LoadError
  ActiveRecord::Base.logger.warn("raspell not loaded; spellcheck not available")

  module Spell
    def self.correct string
      string
    end
  end
end
