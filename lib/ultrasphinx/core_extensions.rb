
require 'chronic'

class Array
  def _flatten_once
    self.inject([]) do |set, element| 
      set + Array(element)
    end
  end
end

class Object
  def _metaclass 
    class << self
      self
    end
  end
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

class Hash
  def _coerce_basic_types
    Hash[*self.map do |key, value|
      [key.to_sym,
        if value.respond_to?(:to_i) && value.to_i.to_s == value
          value.to_i
        elsif value == ""
          nil
        elsif value.is_a? String
          value.to_sym
        else
          value
        end]
      end._flatten_once]
  end
end
