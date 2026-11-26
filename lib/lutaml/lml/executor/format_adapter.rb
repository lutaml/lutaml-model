# frozen_string_literal: true

module Lutaml
  module Lml
    class Executor
      # Pluggable format adapter registry. Adapters handle the actual
      # I/O for a given format (CSV, XML, etc.).
      #
      # Each adapter must implement:
      #   .import(imp, compiled:) — read external data, return array of instances
      #   .export(exp, instances, compiled:) — write instances to external format
      #
      module FormatAdapter
        class AdapterNotFoundError < StandardError; end

        @adapters = {}

        # Built-in adapters resolved by referencing the constant under
        # Executor, which triggers autoload on first access. External
        # adapters can still register via `register`.
        BUILTIN_ADAPTERS = {
          "csv" => :CsvAdapter,
          "xml" => :XmlAdapter
        }.freeze

        # Register an adapter for a format name.
        def self.register(format_name, adapter)
          @adapters[format_name.to_s] = adapter
        end

        # Look up the adapter for a format name.
        def self.resolve(format_name)
          key = format_name.to_s
          return @adapters[key] if @adapters.key?(key)

          builtin = BUILTIN_ADAPTERS[key]
          if builtin
            adapter = Executor.const_get(builtin)
            register(key, adapter)
            return adapter
          end

          raise(AdapterNotFoundError,
            "No adapter registered for format '#{format_name}'")
        end

        # Returns all registered format names.
        def self.registered_formats
          @adapters.keys
        end
      end
    end
  end
end
