
Dir.chdir(File.dirname(__FILE__)) do
  Dir["unit/*.rb", "integration/*.rb"].each do |file|
    puts "\n*** #{file} ***"
    system("ruby #{file}")
  end
end
