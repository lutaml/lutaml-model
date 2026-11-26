# frozen_string_literal: true

require "csv"

module Lutaml
  module Lml
    class Executor
      # CSV format adapter. Reads CSV files and maps rows to hydrated
      # compiled-class instances using column mappings from the import
      # definition. Exports instances back to CSV.
      #
      # Registered for format "csv" via FormatAdapter::BUILTIN_ADAPTERS.
      class CsvAdapter
        extend AdapterHelpers

        # Read a CSV file and map rows to compiled-class instances.
        # Returns an array of hydrated objects.
        #
        # The import definition's attributes provide column mappings:
        #   attribute name = "csv_column_header"
        def self.import(imp, compiled:)
          return [] unless imp.file
          return [] unless imp.attributes&.any?

          mappings = build_column_mappings(imp.attributes)
          target_class = resolve_target_class(imp.attributes, compiled)
          return [] unless target_class

          path = imp.file
          return [] unless File.exist?(path)

          rows = CSV.read(path, headers: true)
          rows.map { |row| build_instance(row, mappings, target_class) }
        end

        # Write instances to a CSV file.
        def self.export(exp, instances, compiled:)
          return if instances.empty?

          path = attribute_value(exp.attributes, "file")
          return unless path && !path.empty?

          first_instance = instances.first
          class_name, target_class = find_class_for_instance(first_instance, compiled)
          return unless target_class

          fields = target_class.attributes.keys
          rows = instances.map do |inst|
            fields.map { |f| extract_attribute_value(inst, f) }
          end

          File.write(path, generate_csv(fields, rows))
        end

        class << self
          private

          def build_column_mappings(attributes)
            Array(attributes).each_with_object({}) do |attr, map|
              next if attr.name == "map_to"
              map[attr.name.to_sym] = attr.value.to_s
            end
          end

          def build_instance(row, mappings, target_class)
            attrs = mappings.each_with_object({}) do |(attr_name, col_name), hash|
              hash[attr_name] = row[col_name]
            end
            target_class.new(**attrs)
          end

          def extract_attribute_value(instance, field_name)
            instance.public_send(field_name)
          rescue NoMethodError
            nil
          end

          def generate_csv(headers, rows)
            CSV.generate do |csv|
              csv << headers
              rows.each { |row| csv << row }
            end
          end
        end
      end
    end
  end
end
