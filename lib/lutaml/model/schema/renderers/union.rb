# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders a Definitions::UnionType into a
        # Lutaml::Model::Type::Value subclass with a cast body whose
        # strategy is chosen from the spec.
        class Union
          def self.render(spec, **)
            new(spec, **).render
          end

          def initialize(spec, indent: 2, module_namespace: nil, register_id: :default)
            @spec = spec
            @indent = indent.is_a?(Integer) ? " " * indent : indent
            @extended_indent = @indent * 2
            @module_namespace = module_namespace
            @modules = module_namespace&.split("::") || []
            @register_id = register_id
          end

          def render
            Templates::UNION_TYPE.result(binding)
          end

          private

          def rendered_class_name = @spec.class_name

          def union_required_files
            files = @spec.required_files
            files.empty? ? "" : "#{files.uniq.join("\n")}\n"
          end

          def union_cast_body
            case @spec.cast_strategy
            when :resolve_type then resolve_type_body
            when :class_refs   then class_refs_body
            end
          end

          def resolve_type_body
            chain = @spec.members.map { |m| resolve_type_call(m) }
            "#{@extended_indent}#{chain.join(" ||\n  ")}\n"
          end

          def resolve_type_call(type_ref)
            "Lutaml::Model::GlobalContext.resolve_type(:#{type_ref.value}, @register).cast(value, options)"
          end

          def class_refs_body
            classes = @spec.members.map { |m| literal_class(m) }.join(", ")
            sp2 = @extended_indent
            <<~BODY
              #{sp2}[#{classes}].each do |t|
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

          def literal_class(type_ref)
            case type_ref.kind
            when :class_ref then type_ref.value
            when :w3c       then "::#{type_ref.value}"
            when :symbol    then "Lutaml::Model::GlobalContext.resolve_type(:#{type_ref.value})"
            end
          end

          def module_opening = ModuleNesting.opening(@modules)
          def module_closing = ModuleNesting.closing(@modules)
          def boilerplate_indent_str = @indent

          def registration_methods
            Registration.methods_block(
              class_name: @spec.class_name,
              module_namespace: @module_namespace,
              indent: @indent,
              lazy: @spec.lazy_register,
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
