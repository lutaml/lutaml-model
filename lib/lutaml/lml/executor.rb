# frozen_string_literal: true

require "forwardable"

module Lutaml
  module Lml
    # Orchestrates instance data I/O: import external data, validate
    # collections, and export to external formats.
    #
    # Format-specific I/O is delegated to registered adapters via the
    # FormatAdapter registry. The core executor only handles the
    # orchestration — it knows *what* to do, adapters know *how*.
    #
    # Usage:
    #   compiled = ModelCompiler.new.compile(models_file)
    #   doc = Lutaml::Lml.parse_document(instances_file)
    #   result = Executor.run(doc, compiled: compiled)
    #   result.instances  # array of hydrated instance objects
    #   result.errors     # array of validation error strings
    #
    class Executor
      autoload :FormatAdapter, "lutaml/lml/executor/format_adapter"
      autoload :AdapterHelpers, "lutaml/lml/executor/adapter_helpers"
      autoload :CsvAdapter, "lutaml/lml/executor/csv_adapter"
      autoload :XmlAdapter, "lutaml/lml/executor/xml_adapter"
      autoload :ConditionEvaluator, "lutaml/lml/executor/condition_evaluator"

      # Result of running the executor: hydrated instances plus any
      # validation errors collected along the way. Delegates array-like
      # methods to instances so existing callers that treated the run
      # return value as an array continue to work.
      Result = Struct.new(:instances, :errors) do
        extend Forwardable

        def_delegators :instances, :length, :each, :map, :[], :empty?
      end

      attr_reader :compiled

      def initialize(compiled:)
        @compiled = compiled
      end

      # Run the full import/validate/export cycle on a parsed document.
      # Returns a Result with hydrated instances and validation errors.
      def self.run(doc, compiled:)
        new(compiled: compiled).run(doc)
      end

      def run(doc)
        instances = run_imports(doc)
        errors = validate_collections(doc, instances)
        run_exports(doc, instances)
        Result.new(instances, errors)
      end

      private

      # --- Import ---

      def run_imports(doc)
        return [] unless doc.instances&.imports&.any?

        doc.instances.imports.flat_map { |imp| import_one(imp) }
      end

      def import_one(imp)
        FormatAdapter.resolve(imp.format_type).import(imp, compiled: @compiled)
      end

      # --- Collection validation ---

      def validate_collections(doc, instances)
        return [] unless doc.instances&.collections

        Array(doc.instances.collections).flat_map do |collection|
          ConditionEvaluator.evaluate(collection, instances)
        end
      end

      # --- Export ---

      def run_exports(doc, instances)
        return unless doc.instances&.exports&.any?

        doc.instances.exports.each do |exp|
          export_one(exp, instances)
        end
      end

      def export_one(exp, instances)
        FormatAdapter.resolve(exp.format_type).export(exp, instances, compiled: @compiled)
      end
    end
  end
end
