
require 'rubygems'
require 'echoe'

Echoe.new("ultrasphinx", `cat CHANGELOG`[/^([\d\.]+)\. /, 1]) do |p|
  
  p.name = "ultrasphinx"
  p.rubyforge_name = "fauna"
  p.description = p.summary = "Ruby on Rails configurator and client to the Sphinx fulltext search engine."
  p.url = "http://blog.evanweaver.com/pages/code#ultrasphinx"
  p.changes = `cat CHANGELOG`[/^([\d\.]+\. .*)/, 1]
  p.need_tar = false
  p.need_tar_gz = true
  
  p.rdoc_pattern = /is_indexed.rb|search.rb|spell.rb|ultrasphinx.rb|README|CHANGELOG|LICENSE/
  if File.exist?(template = "/Users/eweaver/p/allison/trunk/allison/allison.rb")
    p.rdoc_template = template
  end
  
end
