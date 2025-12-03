# frozen_string_literal: true

require_relative "class_definition"

module Lutaml
  module Model
    module Schema
      module Decorators
        class DefinitionCollection
          include Enumerable

          def initialize(definitions_hash)
            @definition_hash = definitions_hash
            @polymorphic_classes = []

            @definitions = definitions_hash.to_h do |name, schema|
              definition = definition_class.new(name, schema)
              @polymorphic_classes << definition if definition.polymorphic?

              [name, definition]
            end

            resolve_polymorphic_base_types!
          end

          def each(&block)
            @definitions.each(&block)
          end

          def transform_values(&block)
            @definitions.transform_values(&block)
          end

          def [](name)
            @definitions[name] || raise("Definition not found: #{name}")
          end

          private

          def definition_class
            Lutaml::Model::Schema::Decorators::ClassDefinition
          end

          def resolve_polymorphic_base_types!
            @polymorphic_classes.each do |poly_class|
              poly_class.polymorphic_attributes.each do |attr|
                resolve_polymorphic_attribute(attr)
              end
            end
          end

          def resolve_polymorphic_attribute(attr)
            child_classes = resolve_child_classes(attr.polymorphic)
            return if child_classes.size < 2

            base_class = find_common_base_class(child_classes)
            return unless base_class

            update_polymorphic_attribute(attr, base_class)
            refactor_subclasses(child_classes, base_class)
          end

          def resolve_child_classes(class_names)
            class_names.filter_map { |name| @definitions[name] }
          end

          def update_polymorphic_attribute(attr, base_class)
            attr.base_class = base_class
            attr.type = base_class.namespaced_name.gsub("_", "::")
          end

          def refactor_subclasses(child_classes, base_class)
            common_keys = base_class.properties.keys.to_set
            (child_classes - [base_class]).each do |child|
              child.base_class = base_class
              child.properties.reject! { |key, _| common_keys.include?(key) }
              base_class.sub_classes << child unless base_class.sub_classes.include?(child)
            end
          end

          def find_common_base_class(class_defs)
            return nil if class_defs.size < 2

            # Get intersection of all property names
            common_props = class_defs.map do |klass|
              klass.properties.keys
            end.reduce(:&)
            return nil if common_props.empty?

            # Look for a class that exactly matches the common properties — assume it's the base
            class_defs.find do |klass|
              klass.properties.keys.to_set == common_props.to_set
            end
          end
        end
      end
    end
  end
end
