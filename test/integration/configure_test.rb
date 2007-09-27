
require "#{File.dirname(__FILE__)}/../integration_helper"

class ConfigureTest < Test::Unit::TestCase
  
  CONF = "#{RAILS_ROOT}/config/ultrasphinx/development.conf"
  
  def test_configuration_hasnt_changed

    File.delete CONF if File.exist? CONF
    Dir.chdir RAILS_ROOT do
      assert_equal true, system("rake us:conf")
    end

    @current = open(CONF).readlines[3..-1]
    @canonical = open(CONF + ".canonical").readlines[3..-1] 
    @canonical.each_with_index do |line, index|
      assert_equal line, @current[index]
    end
  end

end