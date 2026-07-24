# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders a Definitions::RestrictedType into a Ruby class extending
        # a Lutaml::Model::Type::* with Layer-2 facet macros (lazy validation
        # + `.facets` round-trip) and a cast body that mutates options with
        # the eager numeric facet values and delegates to super.
        class RestrictedType < Base
          # XSD base types whose bounds/enumeration values are integer literals.
          INTEGER_BASES = %i[
            integer int long short byte
            positiveInteger nonNegativeInteger negativeInteger nonPositiveInteger
            unsignedLong unsignedInt unsignedShort unsignedByte
          ].freeze

          # Base types whose facet values must be emitted as a `cast` call on
          # the Lutaml type, so the generated literal equals the cast attribute
          # value it is compared against (temporal/boolean/float parse
          # specially). Keyed on both the XSD spelling (`dateTime`, from the XSD
          # compiler) and the snake_case spelling (`date_time`, from the RNG
          # compiler) since both feed this shared renderer.
          CAST_BASES = {
            boolean: "Lutaml::Model::Type::Boolean",
            float: "Lutaml::Model::Type::Float",
            double: "Lutaml::Model::Type::Float",
            date: "Lutaml::Model::Type::Date",
            dateTime: "Lutaml::Model::Type::DateTime",
            date_time: "Lutaml::Model::Type::DateTime",
            time: "Lutaml::Model::Type::Time",
          }.freeze

          # Bases whose bounds render as bare numeric literals, so the eager
          # `options[:min]/[:max]` path is valid Ruby. Every other base
          # (temporal, boolean, string, or a user-defined type) carries a bound
          # that is not a bare literal, so it stays macro-only and the eager
          # path is skipped — the Layer-2 facet macros enforce it lazily.
          EAGER_NUMERIC_BASES = (INTEGER_BASES + %i[decimal float double]).freeze

          def render
            Templates::RESTRICTED_SIMPLE_TYPE.result(binding)
          end

          private

          def rendered_class_name = @spec.class_name
          def parent_class = @spec.parent_class

          def xml_namespace_line
            ns = @spec.namespace_class_name
            ns && "namespace #{ns}"
          end

          def restricted_simple_type_required_files = required_files_block

          # Layer-2 facet macros declared in the class body. They store the
          # facets on the type so generated models validate lazily through
          # RestrictionValidation and round-trip via `.facets` back to XSD.
          def restricted_simple_type_facet_declarations
            f = @spec.facets
            lines = [
              ordered("inclusive", f.min_inclusive, f.max_inclusive),
              ordered("exclusive", f.min_exclusive, f.max_exclusive),
              length_macro,
              # Mirror the eager `%r{#{pattern}}` form (not `pattern.inspect`):
              # a built-in pattern (e.g. anyURI) is stored with live `#{...}`
              # interpolation that `inspect` would escape, matching the literal
              # source instead of the value.
              (Utils.present?(f.pattern) ? "pattern(%r{#{f.pattern}})" : nil),
              enumeration_macro(f.enumerations),
              white_space_macro(f.white_space),
              (Utils.present?(f.total_digits) ? "total_digits #{f.total_digits}" : nil),
              (Utils.present?(f.fraction_digits) ? "fraction_digits #{f.fraction_digits}" : nil),
            ]
            lines.compact.map { |line| "#{@indent}#{line}\n" }.join
          end

          def restricted_simple_type_cast_body
            [
              render_min_max,
              render_pattern,
              render_enumerations,
              render_transform,
            ].compact.join
          end

          # Eager numeric option path, valid only for bases whose bounds are
          # bare numeric literals; other bases are macro-only (see above). The
          # bound is rendered through `literal_for` so a decimal keeps its exact
          # value (`BigDecimal("...")`, not a lossy/`.5`-invalid Float literal).
          def render_min_max
            return nil unless EAGER_NUMERIC_BASES.include?(base_class_name)

            f = @spec.facets
            max = f.max_inclusive || f.max_exclusive
            min = f.min_inclusive || f.min_exclusive
            return nil unless max || min

            out = +""
            out << "#{@extended_indent}options[:max] = #{literal_for(max)}\n" if max
            out << "#{@extended_indent}options[:min] = #{literal_for(min)}\n" if min
            out
          end

          def render_pattern
            p = @spec.facets.pattern
            p && "#{@extended_indent}options[:pattern] = %r{#{p}}\n"
          end

          def render_enumerations
            e = @spec.facets.enumerations
            return nil if e.nil? || e.empty?

            casted = e.map { |v| "super(#{v.inspect})" }.join(", ")
            "#{@extended_indent}options[:values] = [#{casted}]\n"
          end

          def render_transform
            t = @spec.transform_facet
            t && "#{@extended_indent}value = #{t.expression}\n"
          end

          # Format an ordered-facet macro (`inclusive`/`exclusive`) from its
          # base-typed bounds, emitting only the bounds that are present.
          def ordered(macro, min, max)
            args = []
            args << "min: #{literal_for(min)}" if Utils.present?(min)
            args << "max: #{literal_for(max)}" if Utils.present?(max)
            return if args.empty?

            "#{macro} #{args.join(', ')}"
          end

          # Length facets are always plain integers (character/octet counts),
          # independent of the base type: exact `length N`, or a min/max range.
          def length_macro
            f = @spec.facets
            return "length #{f.length}" if Utils.present?(f.length)

            args = []
            args << "min: #{f.min_length}" if Utils.present?(f.min_length)
            args << "max: #{f.max_length}" if Utils.present?(f.max_length)
            return if args.empty?

            "length #{args.join(', ')}"
          end

          def enumeration_macro(enumerations)
            return nil unless Utils.present?(enumerations)

            "enumeration(#{enumerations.map { |v| literal_for(v) }.join(', ')})"
          end

          # xs:whiteSpace is a string-only facet; the runtime macro rejects it
          # on non-string bases. Emit it only for string-derived bases so the
          # generated code loads.
          def white_space_macro(white_space)
            return nil unless string_derived_base? && Utils.present?(white_space)

            "white_space #{white_space.inspect}"
          end

          # The one renderer for base-typed facet values (bounds, enumeration):
          # decimal an exact BigDecimal, temporal/boolean/float a cast value
          # comparable via `<=>`, integer a bare literal, a user-defined base a
          # `cast` on its generated parent class (in scope as this class's
          # superclass), and a built-in string base a quoted string.
          def literal_for(raw)
            name = base_class_name
            return %{BigDecimal("#{raw}")} if name == :decimal
            if (klass = CAST_BASES[name])
              return "#{klass}.cast(#{raw.to_s.inspect})"
            end
            return raw.to_i.to_s if INTEGER_BASES.include?(name)
            unless XmlCompiler::SupportedDataTypes[name]
              return "#{Utils.camel_case(name.to_s)}.cast(#{raw.to_s.inspect})"
            end

            raw.to_s.inspect
          end

          def string_derived_base?
            name = base_class_name
            return false if name == :decimal
            return false if INTEGER_BASES.include?(name)

            !CAST_BASES.key?(name)
          end

          def base_class_name
            @spec.base_class&.to_sym
          end

          def registration_methods
            Registration.methods_block(
              class_name: @spec.class_name,
              module_namespace: @module_namespace,
              indent: @indent,
              lazy: true,
              keep_when_namespaced: @spec.keep_register_when_namespaced,
            )
          end

          def registration_execution
            Registration.execution_line(
              class_name: @spec.class_name,
              module_namespace: @module_namespace,
            )
          end
        end
      end
    end
  end
end
