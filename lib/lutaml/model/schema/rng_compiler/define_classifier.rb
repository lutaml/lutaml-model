# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Detects the shape of a <define> body and builds the corresponding
        # Definitions::* spec for it.
        #
        #   <data type="X"><param ...>...</param></data>      -> RestrictedType
        #   <choice><value>a</value><value>b</value></choice> -> RestrictedType (enum)
        #   <choice><data type="A"/><data type="B"/></choice> -> UnionType
        #
        # Returns nil when the define is structural (contains elements or
        # attributes) — caller falls back to building a Definitions::Model.
        class DefineClassifier
          def self.build(define, class_name)
            new(define, class_name).build
          end

          def initialize(define, class_name)
            @define = define
            @class_name = class_name
          end

          def build
            return nil if structural_define?

            union_type || data_restricted_type || enum_restricted_type
          end

          private

          def structural_define?
            @define.element.any? || @define.attribute.any?
          end

          def union_type
            choice = value_choice
            return nil unless RngHelpers.pure_union_choice?(choice)

            type_refs = Array(choice.data).map do |d|
              symbol = RngCompiler::DATA_TYPE_MAP.fetch(
                d.type, RngCompiler::DEFAULT_DATA_TYPE
              )
              class_string = Lutaml::Model::Type::TYPE_CODES.fetch(
                symbol, Lutaml::Model::Type::TYPE_CODES[:string]
              ).to_s
              Definitions::TypeRef.new(kind: :class_ref, value: class_string)
            end

            Definitions::UnionType.new(
              class_name: @class_name,
              members: type_refs,
              cast_strategy: :class_refs,
            )
          end

          def data_restricted_type
            data = RngHelpers.single(@define.data)
            return nil unless data

            base = RngCompiler::DATA_TYPE_MAP.fetch(
              data.type, RngCompiler::DEFAULT_DATA_TYPE
            )
            Definitions::RestrictedType.new(
              class_name: @class_name,
              parent_class: parent_class_for(base),
              facets: RngHelpers.facet_from_data(data),
            )
          end

          def enum_restricted_type
            choice = value_choice
            return nil unless RngHelpers.pure_value_choice?(choice)

            Definitions::RestrictedType.new(
              class_name: @class_name,
              parent_class: parent_class_for(:string),
              facets: RngHelpers.facet_from_values(choice.value),
            )
          end

          def value_choice
            RngHelpers.single(@define.choice)
          end

          def parent_class_for(base_symbol)
            Lutaml::Model::Type::TYPE_CODES.fetch(
              base_symbol, Lutaml::Model::Type::TYPE_CODES[:string]
            ).to_s
          end
        end
      end
    end
  end
end
