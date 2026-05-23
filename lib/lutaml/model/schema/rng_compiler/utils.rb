# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Shared helpers used by ElementVisitor, DefineClassifier, and
        # ValueTypeResolver. Centralising these here avoids the three-way
        # semantic drift the first refactor introduced (e.g. inconsistent
        # `pure_value_choice?` implementations).
        module Utils
          module_function

          # "card_content" -> "CardContent"
          def camel_case(str)
            str.to_s.split(/[_\-:]/).reject(&:empty?).map do |part|
              part[0].upcase + part[1..].to_s
            end.join
          end

          # "CardContent" or "cardContent" -> "card_content"
          def snake_case(str)
            str.to_s
              .gsub(/([A-Z])(?=[A-Z][a-z])/, '\1_')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .gsub(/[-:]/, "_")
              .downcase
          end

          # Returns the only element of a collection, or nil if the
          # collection is empty or has more than one element. Treats nil as
          # an empty collection.
          def single(collection)
            arr = Array(collection)
            arr.size == 1 ? arr.first : nil
          end

          # Nil-safe non-empty check. For collections, true when `.any?`.
          # For scalars, true when non-nil.
          def present?(value)
            return false if value.nil?
            return value.any? if value.respond_to?(:any?)

            true
          end

          # An RNG node has structural content when any of its element /
          # ref / attribute / choice / group / optional / repetition
          # children are populated. Used to decide whether a container
          # needs its own GeneratedClass or can be expressed as a typed
          # leaf attribute.
          def structural_content?(node)
            return false unless node

            STRUCTURAL_CHILD_NAMES.any? do |attr|
              node.respond_to?(attr) && Array(node.public_send(attr)).any?
            end
          end

          # True when `node` has branching structure that needs its own
          # class. Pure value-choices and `<ref>`s to simple types are NOT
          # branching — they're typed leaves. Used by ValueTypeResolver to
          # decide whether a container can be expressed as a typed
          # attribute rather than its own class.
          def branching_structural?(node)
            return false unless node

            non_leaf = STRUCTURAL_CHILD_NAMES - %i[choice ref]
            return true if non_leaf.any? do |attr|
              node.respond_to?(attr) && Array(node.public_send(attr)).any?
            end

            return false unless node.respond_to?(:choice)

            Array(node.choice).any? { |c| !pure_value_choice?(c) }
          end

          # Build a Restriction from an array of <value> elements (each
          # contributing one enumeration entry).
          def restriction_from_values(values)
            restriction = Restriction.new
            Array(values).each { |v| restriction.add_enumeration(v.value) }
            restriction
          end

          # True iff `choice` is a <choice> consisting purely of <value>
          # alternatives (no <element>, <ref>, or <data>). Single source of
          # truth — used to be defined inconsistently in 3 places.
          def pure_value_choice?(choice)
            return false unless choice
            return false unless choice.respond_to?(:value) && Array(choice.value).any?

            %i[element ref data].none? do |attr|
              choice.respond_to?(attr) && Array(choice.public_send(attr)).any?
            end
          end

          # True iff `choice` is a union: at least 2 <data> alternatives
          # and no other content.
          def pure_union_choice?(choice)
            return false unless choice
            return false unless choice.respond_to?(:data) && Array(choice.data).size >= 2

            %i[element ref value].none? do |attr|
              choice.respond_to?(attr) && Array(choice.public_send(attr)).any?
            end
          end

          # Build a Restriction from an RNG <data>'s <param> children.
          def restriction_from_data(data)
            restriction = Restriction.new
            Array(data.param).each do |param|
              restriction.add_param(param.name, param.value.to_s)
            end
            restriction
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
