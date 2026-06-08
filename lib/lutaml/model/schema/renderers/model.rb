# frozen_string_literal: true

require "erb"
require_relative "../templates"
require_relative "../module_nesting"
require_relative "registration"
require_relative "member_decls"
require_relative "mappings"

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders a Definitions::Model into a Lutaml::Model::Serializable
        # subclass as Ruby source. Member-declaration and xml-mapping
        # rendering is delegated to MemberDecls and Mappings.
        class Model
          def self.render(spec, **options)
            new(spec, **options).render
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
            Templates::SERIALIZABLE_CLASS.result(binding)
          end

          private

          def rendered_class_name = @spec.class_name
          def serializable_class_parent = @spec.parent_class
          def serializable_class_required_files = format_files(@spec.required_files)
          def serializable_class_documentation = format_doc_block(@spec.documentation)
          def serializable_class_imports = render_imports

          def serializable_class_attributes
            MemberDecls.render(
              @spec.members,
              indent: @indent,
              base_indent: @indent,
              text_content: @spec.text_content,
              simple_content: @spec.simple_content,
            )
          end

          def xml_attribute_mappings
            Mappings.render(@spec.members, indent: @extended_indent, base_indent: @indent)
          end

          def xml_root_directive_line
            case @spec.xml_root.kind
            when :element   then %(element "#{@spec.xml_root.name}")
            when :type_name then %(type_name "#{@spec.xml_root.name}")
            end
          end

          def xml_namespace_line
            ns = @spec.namespace_class_name
            ns && "namespace #{ns}"
          end

          def xml_mixed_content? = @spec.mixed
          def xml_text_content? = @spec.text_content

          def xml_extra_mappings
            @spec.simple_content ? %(#{@extended_indent}map_content to: :content\n) : ""
          end

          def module_opening = ModuleNesting.opening(@modules)
          def module_closing = ModuleNesting.closing(@modules)
          def boilerplate_indent_str = @indent

          def registration_methods
            Registration.methods_block(
              class_name: @spec.class_name,
              module_namespace: @module_namespace,
              indent: @indent,
            )
          end

          def registration_execution
            Registration.execution_line(
              class_name: @spec.class_name,
              module_namespace: @module_namespace,
            )
          end

          def format_files(files)
            return "" if files.empty? || @module_namespace

            files.uniq.join("\n") + "\n"
          end

          def format_doc_block(doc)
            return "" if Utils.blank?(doc&.to_s&.strip)

            doc.to_s.lines.map { |line| "# #{line.strip}\n" }.join
          end

          def render_imports
            @spec.imports.map { |name| "#{@indent}import_model #{name}\n" }.join
          end
        end
      end
    end
  end
end
