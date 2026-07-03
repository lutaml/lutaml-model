# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # RNG-specific helpers used by ElementVisitor, DefineClassifier, and
        # ValueTypeResolver. Centralising these here avoids the three-way
        # semantic drift the first refactor introduced (e.g. inconsistent
        # `pure_value_choice?` implementations).
        module RngHelpers
          module_function

          # True if the compiled define renders as a value type (RestrictedType
          # or UnionType) rather than its own Serializable class. Single
          # source of truth — used by ElementVisitor and ValueTypeResolver.
          def simple_type?(klass)
            klass.is_a?(Definitions::RestrictedType) ||
              klass.is_a?(Definitions::UnionType)
          end

          # True iff `klass` is a fragment model (no rooted xml element).
          def fragment_model?(klass)
            klass.is_a?(Definitions::Model) && klass.xml_root.kind == :fragment
          end

          # Returns the only element of a collection, or nil if the
          # collection is empty or has more than one element. Treats nil as
          # an empty collection.
          def single(collection)
            arr = Array(collection)
            arr.size == 1 ? arr.first : nil
          end

          # An RNG node has structural content when any of its element /
          # ref / attribute / choice / group / optional / repetition
          # children are populated.
          def structural_content?(node)
            node && present_children?(node, STRUCTURAL_CHILD_NAMES)
          end

          # True iff any of `attrs` is a populated array-child of `node`.
          def present_children?(node, attrs)
            attrs.any? do |attr|
              node.respond_to?(attr) && Array(node.public_send(attr)).any?
            end
          end

          # True when `node` has branching structure that needs its own
          # class. Pure value-choices and `<ref>`s to simple types are NOT
          # branching — they're typed leaves.
          def branching_structural?(node)
            return false unless node

            non_leaf = STRUCTURAL_CHILD_NAMES - %i[choice ref]
            return true if present_children?(node, non_leaf)

            return false unless node.respond_to?(:choice)

            Array(node.choice).any? { |c| !pure_value_choice?(c) }
          end

          # True iff `choice` is a <choice> consisting purely of <value>
          # alternatives (no <element>, <ref>, <data>, or <text>). A <text>
          # alternative subsumes the literals, so `text | "x"` is a plain
          # string, not an enum restricted to "x".
          def pure_value_choice?(choice)
            return false unless choice
            return false unless choice.respond_to?(:value) && Array(choice.value).any?
            return false if choice.respond_to?(:text) && Utils.present?(choice.text)

            !present_children?(choice, %i[element ref data])
          end

          # True iff `choice` is a union: at least 2 <data> alternatives
          # and no other content.
          def pure_union_choice?(choice)
            return false unless choice
            return false unless choice.respond_to?(:data) && Array(choice.data).size >= 2

            !present_children?(choice, %i[element ref value])
          end

          # Build a Definitions::Facet from an RNG <data>'s <param> children.
          def facet_from_data(data)
            facet = Definitions::Facet.new
            Array(data.param).each do |param|
              apply_param(facet, param.name, param.value.to_s)
            end
            facet
          end

          # Build a Definitions::Facet from an array of <value> elements.
          def facet_from_values(values)
            Definitions::Facet.new(
              enumerations: Array(values).map(&:value),
            )
          end

          # Snake_case symbol used as the registry key for a generated
          # simple-type/union-type/namespace class.
          def type_symbol(class_name)
            Utils.snake_case(class_name).to_sym
          end

          # A class name derived from base_name that does not collide with an
          # existing key in `classes` (appends 2, 3, ... on collision).
          def unique_class_name(classes, base_name)
            return base_name unless classes.key?(base_name)

            counter = 2
            counter += 1 while classes.key?("#{base_name}#{counter}")
            "#{base_name}#{counter}"
          end

          # Maps an RNG/XSD base symbol to its Ruby parent class string,
          # defaulting to the string type when unknown.
          def parent_class_for(base_symbol)
            Lutaml::Model::Type::TYPE_CODES.fetch(
              base_symbol, Lutaml::Model::Type::TYPE_CODES[:string]
            ).to_s
          end

          # A decimal-based restricted type renders `BigDecimal(...)` facet
          # literals, so the generated file must require bigdecimal to load.
          def required_files_for(base_symbol)
            base_symbol == :decimal ? [%(require "bigdecimal")] : []
          end

          def apply_param(facet, name, value)
            case name
            when "minInclusive" then facet.min_inclusive = numeric_or_string(value)
            when "maxInclusive" then facet.max_inclusive = numeric_or_string(value)
            when "minExclusive" then facet.min_exclusive = numeric_or_string(value)
            when "maxExclusive" then facet.max_exclusive = numeric_or_string(value)
            when "minLength"    then facet.min_length = value.to_i
            when "maxLength"    then facet.max_length = value.to_i
            when "length"       then facet.length = value.to_i
            when "pattern"      then facet.pattern = value
            end
          end

          def numeric_or_string(value)
            return value.to_i if /\A-?\d+\z/.match?(value)

            # Keep a fractional bound as its exact lexical string; casting through
            # Float would truncate a high-precision decimal before it reaches the
            # `BigDecimal("...")` facet literal (mirrors the XSD compiler).
            value
          end

          STRUCTURAL_CHILD_NAMES = %i[
            element ref attribute choice group
            optional zeroOrMore oneOrMore
          ].freeze
        end
      end
    end
  end
end
