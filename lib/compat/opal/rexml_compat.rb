# frozen_string_literal: true

# Vendored from lutaml/moxml 0.5.167's lib/compat/opal/rexml_compat.rb
# (the compat surface moxml 0.6 no longer ships). The shadows under
# rexml/ patch the REXML stdlib gem for Opal — multi-byte escape
# regexes in rexml/source.rb, namespace resolution, text decoding and
# the baseparser scanner — which the Opal boot requires on every
# moxml line. Loaded by the Opal Rakefile before spec_helper.
require "corelib/array/pack"

# backtick_javascript: true

require "corelib/array/pack"

unless defined?(StringScanner::Version)
  class StringScanner
    Version = "3.0.8"
  end
end

unless String.method_defined?(:force_encoding)
  class String
    def force_encoding(*)
      self
    end
  end
end

unless defined?(Encoding)
  module ::Encoding
    UTF_8 = "UTF-8"
    ASCII_8BIT = "ASCII-8BIT"
  end
end

unless String.method_defined?(:encode)
  class String
    def encode(*)
      self
    end
  end
end

# Opal defines mutable String methods as raising NotImplementedError.
# Override with functional equivalents that return new strings.
class String
  def <<(str)
    `return self + #{str}.to_s`
  end

  def chomp!(sep = nil)
    `
      var r = #{chomp(sep)};
      return r === self ? nil : r;
    `
  end

  def gsub!(pattern, replacement, &block)
    `
      var r = #{gsub(pattern, replacement, &block)};
      return r === self ? nil : r;
    `
  end

  def squeeze!(*sets)
    `
      var r = #{squeeze(*sets)};
      return r === self ? nil : r;
    `
  end

  def strip!
    `
      var r = #{strip};
      return r === self ? nil : r;
    `
  end
end

class StringIO
  def <<(str)
    write(str)
    self
  end
end
