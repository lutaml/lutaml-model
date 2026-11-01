# frozen_string_literal: false

require "stringio"
require "strscan"

require "rexml/encoding"

module REXML
  if defined?(StringScanner::Version) && StringScanner::Version < "1.0.0"
    module StringScannerCheckScanString
      refine StringScanner do
        def check(pattern)
          pattern = /#{Regexp.escape(pattern)}/ if pattern.is_a?(String)
          super
        end

        def scan(pattern)
          pattern = /#{Regexp.escape(pattern)}/ if pattern.is_a?(String)
          super
        end

        def match?(pattern)
          pattern = /#{Regexp.escape(pattern)}/ if pattern.is_a?(String)
          super
        end

        def skip(pattern)
          pattern = /#{Regexp.escape(pattern)}/ if pattern.is_a?(String)
          super
        end
      end
    end
    using StringScannerCheckScanString
  end

  class SourceFactory
    def self.create_from(arg)
      if arg.respond_to?(:read) &&
          arg.respond_to?(:readline) &&
          arg.respond_to?(:nil?) &&
          arg.respond_to?(:eof?)
        if RUBY_ENGINE == "opal"
          # Opal's StringScanner lacks <<, so use Source (full-string) instead
          # of IOSource (streaming). Read everything upfront.
          Source.new(arg.read, nil)
        else
          IOSource.new(arg)
        end
      elsif arg.respond_to? :to_str
        if RUBY_ENGINE == "opal"
          Source.new(arg, nil)
        else
          IOSource.new(StringIO.new(arg))
        end
      elsif arg.is_a? Source
        arg
      else
        raise "#{arg.class} is not a valid input stream.  It must walk \nlike either a String, an IO, or a Source."
      end
    end
  end

  class Source
    include Encoding

    attr_reader :line, :encoding

    module Private
      SPACES_PATTERN = /\s+/
      SCANNER_RESET_SIZE = 100000
      PRE_DEFINED_TERM_PATTERNS = {}
      pre_defined_terms = ["'", '"', "<", "]]>", "?>"]
      # Opal's StringScanner requires RegExp objects, not strings.
      pre_defined_terms.each do |term|
        PRE_DEFINED_TERM_PATTERNS[term] = /#{Regexp.escape(term)}/
      end
      PRE_DEFINED_TERM_PATTERNS.freeze
    end
    private_constant :Private

    def initialize(arg, encoding = nil)
      @orig = arg
      @scanner = StringScanner.new(@orig)
      if encoding
        self.encoding = encoding
      else
        detect_encoding
      end
      @line = 0
      @encoded_terms = {}
    end

    def buffer
      @scanner.rest
    end

    def drop_parsed_content
      if @scanner.pos > Private::SCANNER_RESET_SIZE
        @scanner = StringScanner.new(@scanner.rest)
      end
    end

    def buffer_encoding=(encoding)
      # no-op under Opal (no Encoding support)
    end

    def encoding=(enc)
      return unless super

      encoding_updated
    end

    def read(term = nil); end

    def read_until(term)
      pattern = Private::PRE_DEFINED_TERM_PATTERNS[term] || /#{Regexp.escape(term)}/
      data = @scanner.scan_until(pattern)
      unless data
        data = @scanner.rest
        @scanner.pos = @scanner.string.bytesize
      end
      data
    end

    def ensure_buffer; end

    def match(pattern, cons = false)
      pattern = Regexp.new(Regexp.escape(pattern)) if pattern.is_a?(String)
      if cons
        @scanner.scan(pattern).nil? ? nil : @scanner
      else
        @scanner.check(pattern).nil? ? nil : @scanner
      end
    end

    def match?(pattern, cons = false)
      pattern = Regexp.new(Regexp.escape(pattern)) if pattern.is_a?(String)
      window = @scanner.peek(4096)
      return false if window.empty?

      m = pattern.match(window)
      return false unless m && m.begin(0) == 0

      @scanner.pos += m[0].length if cons
      true
    end

    def skip_spaces
      @scanner.skip(Private::SPACES_PATTERN) ? true : false
    end

    def position
      @scanner.pos
    end

    def position=(pos)
      @scanner.pos = pos
    end

    def peek_byte
      @scanner.peek_byte
    end

    def scan_byte
      @scanner.scan_byte
    end

    def empty?
      @scanner.eos?
    end

    def current_line
      lines = @orig.split
      res = lines.grep @scanner.rest[0..30]
      res = res[-1] if res.is_a? Array
      lines.index(res) if res
    end

    private

    if RUBY_ENGINE == "opal"
      def detect_encoding
        self.encoding = "UTF-8"
      end
    else
      def detect_encoding
        scanner_encoding = @scanner.rest.encoding
        detected_encoding = "UTF-8"
        begin
          @scanner.string.force_encoding("ASCII-8BIT")
          if @scanner.scan(/\xfe\xff/n)
            detected_encoding = "UTF-16BE"
          elsif @scanner.scan(/\xff\xfe/n)
            detected_encoding = "UTF-16LE"
          elsif @scanner.scan(/\xef\xbb\xbf/n)
            detected_encoding = "UTF-8"
          end
        ensure
          @scanner.string.force_encoding(scanner_encoding)
        end
        self.encoding = detected_encoding
      end
    end

    def encoding_updated
      if @encoding == "UTF-8"
        @to_utf = false
      else
        @scanner = StringScanner.new(decode(@scanner.rest))
        @to_utf = true
      end
    end
  end
end
