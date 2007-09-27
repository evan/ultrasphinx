
Dir.chdir(File.dirname(__FILE__)) do
  Dir["unit/*.rb", "integration/*.rb"].each do |file|
    puts "*** #{file} ***"
    system("ruby #{file}")
  end
end
