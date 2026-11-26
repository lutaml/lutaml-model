# frozen_string_literal: true

require 'delegate'

module Lutaml
  module Lml
    # Normalizes pipeline input (String, StringIO, File, Tempfile) behind
    # one interface: full text, filesystem path (or nil), and the
    # directory imports/includes resolve against.
    class Source
      attr_reader :input

      def self.wrap(input)
        input.is_a?(Source) ? input : new(input)
      end

      def initialize(input)
        @input = input
      end

      def read
        return @input if @input.is_a?(String)

        @input.rewind
        @input.read
      end

      # Filesystem path, or nil for anonymous input (String/StringIO).
      def path
        io = unwrapped
        io.is_a?(File) ? io.path : nil
      end

      def base_dir
        path ? File.dirname(path) : Dir.pwd
      end

      private

      # Tempfile delegates to File (it is not a File subclass on
      # Ruby >= 3.4), so unwrap before type checks.
      def unwrapped
        io = @input
        io = io.__getobj__ while io.is_a?(Delegator)
        io
      end
    end
  end
end
