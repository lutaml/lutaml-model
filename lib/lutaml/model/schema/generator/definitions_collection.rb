# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Generator
        class DefinitionsCollection
          class << self
            include SharedMethods

            def from_class(klass)
              collection = new
              register_definition(collection, klass)
              collection
            end

            def process_attributes(collection, klass, seen = {})
              register = extract_register_from(klass)
              klass.attributes.each_value do |attribute|
                if attribute.union?
                  process_union_members(collection, attribute, seen)
                elsif attribute.serializable?(register)
                  process_attribute(collection, attribute, register, seen)
                end
              end
            end

            # A union attribute's type is Type::Union, not a model, so collect
            # definitions for each of its Serializable members directly (a
            # union schema emits a $ref per model member).
            def process_union_members(collection, attribute, seen = {})
              attribute.union_member_types.each do |member|
                next unless member.is_a?(::Class) &&
                  member.include?(Lutaml::Model::Serialize)

                register_definition(collection, member, seen)
              end
            end

            def process_attribute(collection, attribute, register, seen = {})
              attr_type = Lutaml::Model::GlobalContext.resolve_type(
                attribute.type, register
              )
              register_definition(collection, attr_type, seen)

              process_polymorphic_types(collection, attribute, seen)
            end

            def process_polymorphic_types(collection, attribute, seen = {})
              return unless attribute.options&.[](:polymorphic)

              attribute.options[:polymorphic].each do |child|
                register_definition(collection, child, seen)
              end
            end

            # Recursive models (Node#child → Node, or longer include
            # cycles) are valid; the seen-set registers each class once
            # and lets property references point at the shared $defs
            # entry instead of recursing (#863).
            def register_definition(collection, klass, seen = {})
              return collection if seen[klass]

              seen[klass] = true
              collection << Definition.new(klass)
              process_attributes(collection, klass, seen)
              collection
            end
          end

          attr_reader :definitions

          def initialize(definitions = [])
            @definitions = definitions.map do |definition|
              next definition if definition.is_a?(Definition)

              Definition.new(definition)
            end
          end

          def to_schema
            definitions.each_with_object({}) do |definition, schema|
              schema.merge!(definition.to_schema)
            end
          end

          def add_definition(definition)
            @definitions ||= []
            @definitions << definition
          end
          alias << add_definition
          alias push add_definition

          def merge(collection)
            @definitions ||= []

            if collection.is_a?(Array)
              @definitions.concat(collection)
            else
              @definitions.concat(collection.definitions)
            end
          end
        end
      end
    end
  end
end
