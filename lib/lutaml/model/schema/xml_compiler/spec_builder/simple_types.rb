# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SpecBuilder
          # Builds Definitions::RestrictedType / Definitions::UnionType
          # specs from XSD <xs:simpleType> AST nodes, including the
          # facet container that lives on the restricted type.
          #
          # Stateless. XSD built-in metadata comes from
          # XmlCompiler::SupportedDataTypes; the back-reference to the
          # parent SpecBuilder is kept for symmetry with other sub-builders.
          class SimpleTypes
            def initialize(parent)
              @parent = parent
            end

            def build(simple_type)
              if (union = simple_type.union)
                build_union_type(simple_type.name, union.member_types.split)
              else
                build_restricted_type(simple_type.name, simple_type.restriction)
              end
            end

            def build_supported(name, info)
              base = Utils.base_class_snake_case(info[:class_name])
              validations = info[:validations] || {}
              facet = Definitions::Facet.new(
                min_inclusive: validations[:min_inclusive],
                max_inclusive: validations[:max_inclusive],
                pattern: validations[:pattern],
              )
              transform = validations[:transform] &&
                Definitions::TransformFacet.new(expression: validations[:transform])

              Definitions::RestrictedType.new(
                class_name: Utils.camel_case(name),
                parent_class: restricted_parent_class(base),
                facets: facet,
                transform_facet: transform,
                required_files: supported_required_files(base),
                keep_register_when_namespaced: true,
              )
            end

            private

            def build_union_type(name, member_type_names)
              type_refs = member_type_names.map do |raw|
                snake = Utils.snake_case(Utils.last_of_split(raw))
                Definitions::TypeRef.new(kind: :symbol, value: snake)
              end
              Definitions::UnionType.new(
                class_name: Utils.camel_case(name),
                members: type_refs,
                cast_strategy: :resolve_type,
                required_files: union_required_files(member_type_names),
                lazy_register: true,
                keep_register_when_namespaced: true,
              )
            end

            def union_required_files(member_type_names)
              member_type_names.filter_map do |raw|
                local = Utils.last_of_split(raw)
                next if skippable?(local)

                %(require_relative "#{Utils.snake_case(local)}")
              end
            end

            def build_restricted_type(name, restriction)
              restriction_base = restriction&.base
              base_class = restriction_base&.split(":")&.last
              facet = restriction ? build_facet(restriction) : Definitions::Facet.new

              Definitions::RestrictedType.new(
                class_name: Utils.camel_case(name),
                parent_class: restricted_parent_class(base_class),
                facets: facet,
                transform_facet: nil,
                required_files: restricted_required_files(base_class),
                keep_register_when_namespaced: true,
              )
            end

            def restricted_parent_class(base_class)
              type_info = SupportedDataTypes[base_class&.to_sym]
              return type_info[:class_name] if type_info&.dig(:skippable)
              return Utils.camel_case(base_class.to_s) if !type_info&.dig(:skippable) && Utils.present?(base_class)

              "Lutaml::Model::Type::Value"
            end

            def restricted_required_files(base_class)
              return [] if Utils.blank?(base_class)

              return [%(require "bigdecimal")] if base_class == "decimal"
              return [] if SupportedDataTypes.skippable?(base_class)

              [%(require_relative "#{Utils.snake_case(base_class)}")]
            end

            def supported_required_files(base_class)
              return [] if Utils.blank?(base_class) || SupportedDataTypes.skippable?(base_class)

              [%(require_relative "#{Utils.snake_case(base_class)}")]
            end

            def skippable?(local)
              SupportedDataTypes.skippable?(local)
            end

            # ----- Facets ---------------------------------------------------

            def build_facet(restriction)
              Definitions::Facet.new(
                max_length: pick_minmax(restriction.max_length, :min),
                min_length: pick_minmax(restriction.min_length, :max),
                min_inclusive: pick_minmax(restriction.min_inclusive, :max),
                max_inclusive: pick_minmax(restriction.max_inclusive, :min),
                max_exclusive: pick_minmax(restriction.max_exclusive, :max),
                min_exclusive: pick_minmax(restriction.min_exclusive, :min),
                length: restriction.length&.any? ? restriction_length(restriction.length) : nil,
                pattern: build_pattern(restriction.pattern),
                enumerations: restriction.enumeration&.any? ? restriction.enumeration.map(&:value) : nil,
              )
            end

            def pick_minmax(field_value, method)
              return nil unless field_value&.any?

              field_value.map(&:value).public_send(method).to_s
            end

            def restriction_length(lengths)
              lengths.map { |l| { value: l.value, fixed: l.fixed } }
            end

            def build_pattern(patterns)
              return nil if Utils.blank?(patterns)

              patterns.map { |p| "(#{p.value})" }.join("|")
            end
          end
        end
      end
    end
  end
end
