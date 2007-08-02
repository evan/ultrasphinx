
require 'rubygems'
require 'echoe'

Echoe.new("ultrasphinx", `cat CHANGELOG`[/^v([\d\.]+)\. /, 1]) do |p|
  
  p.name = "ultrasphinx"
  p.rubyforge_name = "fauna"
  p.description = p.summary = "Ruby on Rails configurator and client to the Sphinx fulltext search engine."
  p.url = "http://blog.evanweaver.com/pages/code#ultrasphinx"
  p.changes = `cat CHANGELOG`[/^v([\d\.]+\. .*)/, 1]
  
  p.docs_host = "blog.evanweaver.com:~/www/snax/public/files/doc/"
  p.need_tar = false
  p.need_tar_gz = true  
  
  p.rdoc_pattern = /is_indexed.rb|search.rb|spell.rb|ultrasphinx.rb|\.\/README|CHANGELOG|LICENSE/
    
end
