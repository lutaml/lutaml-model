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
                base_class: base,
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
                base_class: base_class,
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
                max_exclusive: pick_minmax(restriction.max_exclusive, :min),
                min_exclusive: pick_minmax(restriction.min_exclusive, :max),
                length: pick_minmax(restriction.length, :min),
                pattern: build_pattern(restriction.pattern),
                enumerations: restriction.enumeration&.any? ? restriction.enumeration.map(&:value) : nil,
                white_space: single_facet(restriction.white_space, &:to_sym),
                total_digits: single_facet(restriction.total_digits, &:to_i),
                fraction_digits: single_facet(restriction.fraction_digits, &:to_i),
              )
            end

            # Pick the tightest bound as its exact lexical string. A single
            # value (the only schema-valid case) is returned verbatim so a
            # decimal keeps its precision; a repeated bound is ordered by
            # numeric magnitude (not lexical order, under which "5" > "10"),
            # falling back to lexical order for non-numeric temporal bounds.
            def pick_minmax(field_value, method)
              return nil unless field_value&.any?

              values = field_value.map(&:value)
              return values.first if values.one?

              values.public_send(:"#{method}_by") { |v| comparable_bound(v) }
            end

            # Lazy, guarded require (mirrors Type::Decimal) so this Opal-booted
            # file has no load-time bigdecimal dependency; the XSD compiler is a
            # native-only path, so this only runs under MRI.
            def comparable_bound(value)
              require "bigdecimal" unless defined?(BigDecimal)
              BigDecimal(value.to_s)
            rescue ArgumentError
              value.to_s
            end

            # Carry a single-valued facet (whiteSpace/totalDigits/
            # fractionDigits), normalizing its lexical value through the block.
            def single_facet(field_value)
              return nil unless field_value&.any?

              yield(field_value.first.value)
            end

            # Multiple <xsd:pattern> in one restriction are alternatives (OR),
            # each grouped so a `|` inside one does not leak across; a single
            # pattern needs no grouping and is carried verbatim so it round-trips
            # exactly (and keeps any live `#{...}` interpolation, e.g. anyURI).
            def build_pattern(patterns)
              return nil if Utils.blank?(patterns)

              values = patterns.map(&:value)
              values.one? ? values.first : values.map { |v| "(#{v})" }.join("|")
            end
          end
        end
      end
    end
  end
end
