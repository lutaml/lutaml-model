# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD union simple-type renderer — for `<xs:simpleType>` with
        # `<xs:union>`. Inherits the full render flow from
        # Lutaml::Model::Schema::UnionTypeRenderer; the XSD cast strategy
        # is `||`-chained `Lutaml::Model::GlobalContext.resolve_type` lookups
        # against the register (differs from RNG's each+rescue).
        class UnionSimpleType < Lutaml::Model::Schema::UnionTypeRenderer
          include SimpleTypeBase

          attr_accessor :unions

          def initialize(name, unions = [])
            super()
            @class_name = name
            @unions = unions
            @module_namespace = nil
          end

          # --- UnionTypeRenderer overrides ---

          def union_required_files
            return "" if @module_namespace

            unions.filter_map do |union|
              next if SimpleType::SUPPORTED_DATA_TYPES.dig(Utils.last_of_split(union).to_sym, :skippable)

              "require_relative \"#{down_union_class_name(union)}\""
            end.join("\n")
          end

          def union_cast_body
            sp2 = boilerplate_indent_str * 2
            body = unions.map do |union|
              "#{sp2}Lutaml::Model::GlobalContext.resolve_type(:#{down_union_class_name(union)}, @register).cast(value, options)"
            end.join(" ||\n  ")
            "#{body}\n"
          end

          private

          def down_union_class_name(union)
            Utils.snake_case(Utils.last_of_split(union))
          end
        end
      end
    end
  end
end
