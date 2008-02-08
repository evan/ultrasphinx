#!/usr/bin/env ruby

require "#{File.dirname(__FILE__)}/../test_helper"
require 'benchmark'
require 'ruby-prof'

prof = ENV['PROF']

S = Ultrasphinx::Search
E = Ultrasphinx::UsageError

RubyProf.start if prof

Benchmark.bm(20) do |x|
  x.report("simple") do 
    100.times do
      @s = S.new(:query => 'seller').run
    end
  end
end

RubyProf::GraphPrinter.new(RubyProf.stop).print(STDOUT, 0) if prof  
