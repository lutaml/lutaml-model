# frozen_string_literal: true

require_relative "standard_adapter"

module Lutaml
  module Json
    module Adapter
      # JSON parsing over the yeptris engine: Yeptris::JSON.load targets
      # exact JSON.parse semantics (spec-pinned upstream), with a fused
      # native materializer when the loaded libyeptris build carries it.
      # Generation stays on the json gem (the yeptris JSON surface is
      # load-only), so everything else inherits from the standard adapter.
      class YeptrisAdapter < StandardAdapter
        def self.parse(json, _options = {})
          require_engine
          ::Yeptris::JSON.load(json)
        rescue ::Yeptris::JSON::ParseError => e
          raise parser_error(e)
        end

        # The engine require sits outside parse's rescue so a broken
        # install still surfaces its LoadError (the detection fallback's
        # contract) instead of a NameError from the rescue clause.
        def self.require_engine
          require "yeptris"
        end
        private_class_method :require_engine

        # The parse-error contract is the standard adapter's: invalid
        # input raises JSON::ParserError regardless of the engine, so
        # consumers' rescue ladders (and this gem's own
        # format_error_types conversion to InvalidFormatError) hold on
        # every adapter. Without the json gem the engine error
        # propagates unchanged.
        def self.parser_error(error)
          return error unless defined?(::JSON::ParserError)

          ::JSON::ParserError.new(error.message)
        end
        private_class_method :parser_error
      end
    end
  end
end
