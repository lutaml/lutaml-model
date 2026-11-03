# frozen_string_literal: true

require_relative "standard_adapter"

module Lutaml
  module Yamls
    module Adapter
      # YAMLS streams over the yeptris engine (libyeptris C11), using the
      # multi-document stream API at Psych parity (yeptris-ruby#354).
      # Inherits the standard adapter's document contract — split fallback
      # on parse failure, nil-document skipping — and swaps only the
      # engine calls.
      class YeptrisAdapter < StandardAdapter
        def self.parse(yamls, _options = {})
          parse_with_stream(yamls)
        end

        # The engine require sits outside parse's rescue so a broken
        # install still surfaces its LoadError instead of degrading to
        # the split lane.
        def self.parse_with_stream(yamls)
          require_engine
          require "yeptris/yaml"

          # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
          results = Yeptris::YAML.load_stream(yamls, schema: :compat_11)
          results.compact
        rescue Yeptris::ParseError => e
          warn "Skipping invalid yaml: #{e.message}"
          parse_with_split(yamls)
        end

        def self.require_engine
          require "yeptris"
        end
        private_class_method :require_engine

        # Same probe contract as the key-value lane's adapter: true only
        # when the native engine loads AND answers a stream parse, so
        # half-initialized installs gate to the standard lane instead of
        # committing and failing mid-load.
        def self.available?
          require_engine
          require "yeptris/yaml"
          # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
          ::Yeptris::YAML.load_stream("---\nprobe: 1\n", schema: :compat_11)
          true
        rescue LoadError, StandardError
          false
        end
      end
    end
  end
end
