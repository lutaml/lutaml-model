# frozen_string_literal: true

module Lutaml
  module Lml
    class Executor
      # Shared helpers for the I/O adapters. Both CsvAdapter and XmlAdapter
      # need to:
      #
      #   - resolve a `map_to` reference to a compiled class
      #   - look up attribute values by name in an import/export definition
      #   - find the compiled class that an instance belongs to (for export)
      #
      # This module owns those three concerns so each adapter can stay
      # focused on its format-specific I/O.
      module AdapterHelpers
        # Returns the compiled class referenced by the `map_to` attribute,
        # or nil if no such attribute or no such compiled class.
        def resolve_target_class(attributes, compiled)
          attr = find_attribute(attributes, "map_to")
          return nil unless attr

          compiled[attr.value.to_s]
        end

        # Returns the string value of the named attribute, or nil.
        def attribute_value(attributes, name)
          attr = find_attribute(attributes, name)
          attr ? attr.value.to_s : nil
        end

        # Walks an attributes collection looking for an entry whose
        # `.name` matches `name`. Returns the attribute, or nil.
        def find_attribute(attributes, name)
          Array(attributes).find { |a| a.name == name }
        end

        # Returns [class_name, klass] for the first compiled class whose
        # instances include `first_instance`, or nil if no match.
        def find_class_for_instance(first_instance, compiled)
          compiled.find { |_name, klass| first_instance.is_a?(klass) }
        end
      end
    end
  end
end
