# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # RNG union type — inherits the full render flow from
        # Lutaml::Model::Schema::UnionTypeRenderer. RNG's cast-body uses
        # an each-loop over hardcoded class refs with rescue (returns the
        # original value if every member fails).
        class UnionType < Lutaml::Model::Schema::UnionTypeRenderer
          include TypeSymbol

          attr_reader :class_name, :member_types
          attr_accessor :fragment

          def initialize(class_name:, member_types:)
            super()
            @class_name = class_name
            @member_types = member_types
            @fragment = true
          end

          # --- UnionTypeRenderer overrides ---

          def rendered_class_name
            class_name
          end

          def union_cast_body
            sp2 = boilerplate_indent_str * 2
            <<~BODY
              #{sp2}[#{type_list}].each do |t|
              #{sp2}  begin
              #{sp2}    casted = t.cast(value, options)
              #{sp2}    return casted unless casted.nil?
              #{sp2}  rescue StandardError
              #{sp2}    next
              #{sp2}  end
              #{sp2}end
              #{sp2}value
            BODY
          end

          # UnionType registers under its type_symbol like SimpleType.
          def registration_methods
            super(type_symbol)
          end

          private

          def type_list
            @member_types.map do |t|
              Lutaml::Model::Type::TYPE_CODES.fetch(
                t, Lutaml::Model::Type::TYPE_CODES[:string]
              )
            end.join(", ")
          end
        end
      end
    end
  end
end
