# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders a Definitions::RestrictedType into a Ruby class extending
        # a Lutaml::Model::Type::* with a cast body that mutates options
        # with facet values and delegates to super.
        class RestrictedType < Base
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

          def restricted_simple_type_cast_body
            [
              render_min_max,
              render_pattern,
              render_enumerations,
              render_transform,
            ].compact.join
          end

          def render_min_max
            f = @spec.facets
            max = f.max_inclusive || f.max_exclusive
            min = f.min_inclusive || f.min_exclusive
            return nil unless max || min

            out = +""
            out << "#{@extended_indent}options[:max] = #{max}\n" if max
            out << "#{@extended_indent}options[:min] = #{min}\n" if min
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
