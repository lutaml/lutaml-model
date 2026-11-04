# frozen_string_literal: true

require_relative "standard_adapter"

module Lutaml
  module Yamls
    module Adapter
      # YAMLS streams over the yeptris engine (libyeptris C11), using the
      # multi-document stream API at Psych parity (yeptris-ruby#354) and,
      # when the engine offers it, the tolerant per-document iterator
      # (yeptris#921): invalid documents skip in place and the valid
      # ones stand — no host-side splitting or re-parsing, ever.
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

          results = []
          if ::Yeptris::YAML.respond_to?(:each_document)
            # Tolerant iteration (yeptris#921): the engine frames the
            # documents and reports failures per document; the host
            # never touches the YAML text.
            # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
            ::Yeptris::YAML.each_document(yamls, schema: :compat_11) do |doc, error|
              warn "Skipping invalid yaml: #{error.message}" if error
              results << doc unless error || doc.nil?
            end
            return results
          end

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
