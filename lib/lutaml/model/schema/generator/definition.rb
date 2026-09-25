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

            # Choice validation: each choice is its own group. Independent
            # choices combine conjunctively (allOf), so a document may
            # satisfy every group at once; a single choice renders its
            # group directly. Nested choices render as a nested group
            # schema, which a document satisfies through its own
            # oneOf/anyOf (#864, #865).
            if type.choice_attributes.any?
              if type.choice_attributes.one?
                @schema[name].merge!(choice_schema(type.choice_attributes.first))
              else
                @schema[name]["allOf"] = type.choice_attributes.map do |choice|
                  choice_schema(choice)
                end
              end
            end

            @schema
          end

          private

          # min == max == 1 makes the members mutually exclusive (oneOf);
          # any other range admits several members together (anyOf with
          # per-member requirement).
          def choice_schema(choice)
            key = choice.min == 1 && choice.max == 1 ? "oneOf" : "anyOf"
            { key => choice_branches(choice) }
          end

          def choice_branches(choice)
            choice.attributes.map do |member|
              if member.is_a?(Lutaml::Model::Choice)
                choice_schema(member)
              else
                {
                  "type" => "object",
                  "properties" => PropertiesCollection.from_attributes(
                    [member], extract_register_from(type)
                  ).to_schema,
                  "required" => [member.name.to_s],
                }
              end
            end
          end

          def properties_to_schema(type)
            PropertiesCollection.from_class(type).to_schema
          end
        end
      end
    end
  end
end
