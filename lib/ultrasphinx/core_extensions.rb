
require 'chronic'

class Array
  def _flatten_once
    self.inject([]){|r, el| r + Array(el)}
  end
end

class Object
  def _metaclass; (class << self; self; end); end
end

class String
  def _to_numeric
    zeroless = self.squeeze(" ").strip.sub(/^0+(\d)/, '\1')
    zeroless.sub!(/(\...*?)0+$/, '\1')
    if zeroless.to_i.to_s == zeroless
      zeroless.to_i
    elsif zeroless.to_f.to_s == zeroless
      zeroless.to_f
    elsif date = Chronic.parse(self)
      date.to_i
    else
      self
    end
  end
end

