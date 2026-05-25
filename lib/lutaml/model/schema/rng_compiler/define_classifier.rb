# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Detects the shape of a <define> body and builds the corresponding
        # generated-class object. Three simple-type shapes are recognised:
        #
        #   <data type="X"><param ...>...</param></data>      -> SimpleType
        #   <choice><value>a</value><value>b</value></choice> -> SimpleType (enum)
        #   <choice><data type="A"/><data type="B"/></choice> -> UnionType
        #
        # Returns nil when the define is structural (contains elements or
        # attributes) — caller falls back to building a GeneratedClass.
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

            union_type || data_simple_type || enum_simple_type
          end

          private

          def structural_define?
            @define.element.any? || @define.attribute.any?
          end

          def union_type
            choice = value_choice
            return nil unless Utils.pure_union_choice?(choice)

            member_types = Array(choice.data).map do |d|
              RngCompiler::DATA_TYPE_MAP.fetch(
                d.type, RngCompiler::DEFAULT_DATA_TYPE
              )
            end
            UnionType.new(class_name: @class_name, member_types: member_types)
          end

          def data_simple_type
            data = Utils.single(@define.data)
            return nil unless data

            SimpleType.new(
              class_name: @class_name,
              base_type: RngCompiler::DATA_TYPE_MAP.fetch(
                data.type, RngCompiler::DEFAULT_DATA_TYPE
              ),
              restriction: Utils.restriction_from_data(data),
            )
          end

          def enum_simple_type
            choice = value_choice
            return nil unless Utils.pure_value_choice?(choice)

            SimpleType.new(
              class_name: @class_name,
              base_type: :string,
              restriction: Utils.restriction_from_values(choice.value),
            )
          end

          def value_choice
            Utils.single(@define.choice)
          end
        end
      end
    end
  end
end
