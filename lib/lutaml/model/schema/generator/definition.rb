# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Generator
        class Definition
          include SharedMethods

          attr_reader :type, :name

          def initialize(type)
            @type = type
            @name = type.name.gsub("::", "_")
          end

          def to_schema
            @schema = {
              name => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => properties_to_schema(type),
              },
            }

            # Choice validation follows the serializer's contract: unset
            # or empty members are omitted from output, and instances that
            # leave a whole group empty are accepted (#869). Members are
            # therefore never `required`; a max:1 group contributes an
            # at-most-one constraint over its members, and independent
            # groups combine conjunctively under allOf. Groups whose range
            # admits several members impose no serialization constraint.
            if type.choice_attributes.any?
              groups = type.choice_attributes
                .select { |choice| choice.max == 1 }
                .map { |choice| { "oneOf" => exclusive_branches(choice) } }

              if groups.one?
                @schema[name].merge!(groups.first)
              elsif groups.any?
                @schema[name]["allOf"] = groups
              end
            end

            @schema
          end

          private

          # Leaves of the group (nested choices collapse into it), as
          # [name, attribute] pairs.
          def choice_leaves(choice)
            choice.attributes.flat_map do |member|
              if member.is_a?(Lutaml::Model::Choice)
                choice_leaves(member)
              else
                [[member.name.to_s, member]]
              end
            end
          end

          # Exactly-one-present construction over the leaves: no leaf, or
          # exactly one leaf present without the others. Accepts the
          # all-empty document the serializer emits; rejects documents
          # with two members of the group at once (max:1).
          def exclusive_branches(choice)
            leaves = choice_leaves(choice)
            names = leaves.map(&:first)
            none = {
              "not" => {
                "anyOf" => names.map { |n| { "required" => [n] } },
              },
            }
            singles = leaves.map do |name, attribute|
              others = names - [name]
              {
                "allOf" => (
                  [{
                    "type" => "object",
                    "properties" => PropertiesCollection.from_attributes(
                      [attribute], extract_register_from(type)
                    ).to_schema,
                    "required" => [name],
                  }] + others.map { |o| { "not" => { "required" => [o] } } }
                ),
              }
            end
            [none] + singles
          end

          def properties_to_schema(type)
            PropertiesCollection.from_class(type).to_schema
          end
        end
      end
    end
  end
end
