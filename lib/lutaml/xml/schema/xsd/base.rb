# frozen_string_literal: true

require "canon"

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Base < Lutaml::Model::Serializable
          XML_DECLARATION_REGEX = /<\?xml[^>]+>\s+/
          ELEMENT_ORDER_IGNORABLE = %w[import include].freeze

          def to_formatted_xml(except: [])
            Canon.format_xml(
              to_xml(except: except),
            ).gsub(XML_DECLARATION_REGEX, "")
          end

          def resolved_element_order
            element_order&.each_with_object(element_order.dup) do |element, array|
              next delete_deletables(array, element) if deletable?(element)

              update_element_array(array, element)
            end
          end

          # Propagate the parsed schema root through the XSD object graph so
          # Liquid helpers can resolve cross-object references consistently.
          def assign_root!(root = self, seen = nil)
            seen ||= {}.compare_by_identity
            return self if seen[self]

            seen[self] = true
            self.lutaml_root = root

            self.class.attributes&.each_key do |attribute_name|
              assign_root_value!(public_send(attribute_name), root, seen)
            end

            self
          end

          def sequence?
            is_a?(Sequence)
          end

          def any?
            is_a?(Any)
          end

          def all?
            is_a?(All)
          end

          def choice?
            is_a?(Choice)
          end

          def annotation?
            is_a?(Annotation)
          end

          def attribute?
            is_a?(Attribute)
          end

          def attribute_group?
            is_a?(AttributeGroup)
          end

          def simple_content?
            is_a?(SimpleContent)
          end

          def complex_content?
            is_a?(ComplexContent)
          end

          def element?
            is_a?(Element)
          end

          def min_occurrences
            return unless respond_to?(:min_occurs)

            @min_occurs&.to_i || 1
          end

          def max_occurrences
            return unless respond_to?(:max_occurs)
            return "*" if @max_occurs == "unbounded"

            @max_occurs&.to_i || 1
          end

          def target_prefix
            xsd_root&.target_namespace_prefix
          end

          def unresolvable_items(array = [], seen = nil)
            seen ||= {}.compare_by_identity
            return array if seen[self]

            seen[self] = true
            resolved_element_order&.each do |element|
              if element.respond_to?(:ref) && element.ref
                if resolvable_reference?(element.ref)
                  element.referenced_object&.unresolvable_items(array, seen)
                else
                  array << element
                end
              elsif element.respond_to?(:unresolvable_items)
                element.unresolvable_items(array, seen)
              end
            end
            array
          end

          liquid do
            map "any?", to: :any?
            map "all?", to: :all?
            map "to_xml", to: :to_xml
            map "choice?", to: :choice?
            map "element?", to: :element?
            map "sequence?", to: :sequence?
            map "attribute?", to: :attribute?
            map "annotation?", to: :annotation?
            map "target_prefix", to: :target_prefix
            map "simple_content?", to: :simple_content?
            map "min_occurrences", to: :min_occurrences
            map "max_occurrences", to: :max_occurrences
            map "to_formatted_xml", to: :to_formatted_xml
            map "complex_content?", to: :complex_content?
            map "attribute_group?", to: :attribute_group?
            map "unresolvable_items", to: :unresolvable_items
            map "resolved_element_order", to: :resolved_element_order
          end

          private

          # Resolve a named object from a root-level collection, taking the
          # schema target prefix into account when references are qualified.
          def find_object(collection, reference = ref)
            find_in_collection(collection, reference) ||
              find_in_related_schemas(collection, reference)
          end

          def reference_local_name(reference)
            reference.to_s.split(":", 2).last
          end

          def reference_prefix(reference)
            parts = reference.to_s.split(":", 2)
            parts.length == 2 ? parts.first : nil
          end

          def builtin_reference?(reference)
            %w[xs xsd xml].include?(reference_prefix(reference))
          end

          def reference_matches?(name, reference)
            return false if name.nil? || reference.nil?
            return true if name == reference
            return false if builtin_reference?(reference)

            reference_local_name(reference) == name
          end

          def resolvable_reference?(reference)
            !builtin_reference?(reference) && !find_object_for_ref(reference).nil?
          end

          def find_object_for_ref(reference)
            if respond_to?(:referenced_object)
              referenced_object
            else
              find_object(collection_for_reference(reference), reference)
            end
          end

          def deletable?(instance)
            instance.text? ||
              ELEMENT_ORDER_IGNORABLE.include?(instance.name)
          end

          def delete_deletables(array, instance)
            array.delete_if { |ins| ins == instance }
          end

          def update_element_array(array, instance)
            index = 0
            array.each_with_index do |element, i|
              next unless element == instance

              method_name = ::Lutaml::Model::Utils.snake_case(instance.name)
              array[i] = Array(send(method_name))[index]
              index += 1
            end
          end

          def assign_root_value!(value, root, seen)
            Array(value).each do |child|
              next unless child.respond_to?(:assign_root!)

              child_root = child.is_a?(Schema) ? child : root
              child.assign_root!(child_root, seen)
            end
          end

          def find_in_collection(collection, reference)
            collection&.find do |object|
              reference_matches?(object.name, reference)
            end
          end

          def find_in_related_schemas(collection, reference)
            collection_name = collection_name_for(collection)
            return unless collection_name

            related_schemas.each do |schema|
              found = find_in_collection(schema.public_send(collection_name),
                                         reference)
              return found if found
            end

            nil
          end

          def collection_name_for(collection)
            return unless xsd_root

            %i[element complex_type simple_type attribute group attribute_group].find do |name|
              xsd_root.public_send(name).equal?(collection)
            end
          end

          def related_schemas(root = xsd_root, seen = nil)
            seen ||= {}.compare_by_identity
            return [] unless root
            return [] if seen[root]

            seen[root] = true
            schemas = []
            %i[import include].each do |collection_name|
              root.public_send(collection_name).each do |schema|
                next unless schema.is_a?(Schema)

                schemas << schema
                schemas.concat(related_schemas(schema, seen))
              end
            end
            schemas
          end

          def collection_for_reference(_reference)
            []
          end

          def xsd_root
            lutaml_root || (self if is_a?(Schema))
          end
        end
      end
    end
  end
end
