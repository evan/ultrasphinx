
require 'rubygems'
require 'echoe'

Echoe.new("ultrasphinx", `cat CHANGELOG`[/^([\d\.]+)\. /, 1]) do |p|
  p.name = "ultrasphinx"
  p.rubyforge_name = "fauna"
  p.description = p.summary = "Ruby on Rails configurator and client to the Sphinx fulltext search engine."
  p.url = "http://blog.evanweaver.com/pages/code#ultrasphinx"
  p.changes = `cat CHANGELOG`[/^([\d\.]+\. .*)/, 1]
end

