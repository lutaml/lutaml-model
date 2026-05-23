# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # One generated Lutaml::Model::Serializable class.
        #
        # Output format matches XmlCompiler::ComplexType: frozen_string_literal
        # header, require "lutaml/model", require_relative for dependencies
        # (when not namespaced), class body, then registration methods +
        # `Klass.register_class_with_id` at the bottom.
        #
        # A class is either "rooted" (a concrete XML element) or "fragment"
        # (a type-only model pulled into other classes via `import_model`).
        #
        # Members can be Attribute (a single attribute) or Choice
        # (a `choice do ... end` block listing alternatives).
        class GeneratedClass
          include ClassBoilerplate

          TEMPLATE = ERB.new(<<~TMPL, trim_mode: "-")
            # frozen_string_literal: true

            require "lutaml/model"
            <%= required_files_lines -%>
            <%= module_opening -%>
            <%= class_documentation_lines -%>
            class <%= class_name %> < Lutaml::Model::Serializable
            <%= member_lines -%>
            <%= imports_lines -%>
            <%= "\n" if member_lines.length.positive? || imports_lines.length.positive? -%>
            <%= sp %>xml do
            <%- unless fragment -%>
            <%= sp2 %>element "<%= xml_name %>"
            <%- end -%>
            <%- if namespace_class -%>
            <%= sp2 %>namespace <%= namespace_class %>
            <%- end -%>
            <%- if mixed -%>
            <%= sp2 %>mixed_content
            <%- end -%>
            <%- if text_content -%>
            <%= sp2 %>map_content to: :content
            <%- end -%>
            <%= mapping_lines -%>
            <%= sp %>end
            <%= registration_methods -%>
            end
            <%= module_closing -%>
            <%= registration_execution -%>
          TMPL

          attr_reader :class_name, :xml_name, :members, :imports
          attr_accessor :mixed, :text_content, :fragment, :documentation,
                        :namespace_class

          def initialize(class_name:, xml_name:, fragment: false,
                         documentation: nil, namespace_class: nil)
            @class_name = class_name
            @xml_name = xml_name
            @members = []
            @imports = []
            @mixed = false
            @text_content = false
            @fragment = fragment
            @documentation = documentation
            @namespace_class = namespace_class
          end

          def add_attribute(spec)
            @members.reject! do |m|
              m.is_a?(Attribute) && m.name == spec.name
            end
            @members << spec
          end

          def add_choice(choice_spec)
            @members << choice_spec
          end

          def add_sequence(sequence_spec)
            @members << sequence_spec
          end

          def add_import(name)
            @imports << name unless @imports.include?(name)
          end

          # Flat view of all Attribute specs (including those nested in
          # Choices and Sequences). Used for dependency analysis.
          def attributes
            @members.flat_map do |m|
              case m
              when Choice   then m.alternatives.flat_map { |a| flatten_alt(a) }
              when Sequence then m.attributes
              else [m]
              end
            end
          end

          def flatten_alt(alt)
            case alt
            when Sequence then alt.attributes
            when Choice   then alt.alternatives.flat_map { |a| flatten_alt(a) }
            else [alt]
            end
          end

          def dependency_class_names
            deps = []
            deps.concat(imports)
            attributes.each do |a|
              deps << a.type if a.type.is_a?(String) && a.type.start_with?(/[A-Z]/)
            end
            deps << @namespace_class if @namespace_class
            deps.uniq
          end

          def render(indent: 2, module_namespace: nil, register_id: :default)
            @indent = indent
            @module_namespace = module_namespace
            @register_id = register_id
            @modules = Array(module_namespace&.split("::"))
            TEMPLATE.result(binding)
          end

          private

          def sp
            " " * @indent
          end

          def sp2
            sp * 2
          end

          def member_lines
            lines = @members.map { |m| render_member_decl(m, sp) }.join
            lines += "#{sp}attribute :content, :string\n" if text_content
            lines
          end

          # Attribute-declaration rendering: Sequence is transparent (members
          # emitted flat); Choice renders as `choice do ... end`; Attribute as
          # a bare `attribute` line preceded by its documentation comment.
          # Matches XmlCompiler attribute-declaration output (XSD
          # Sequence#to_attributes is also flat).
          def render_member_decl(member, indent)
            case member
            when Choice   then render_choice_block(member, indent)
            when Sequence then member.members.map { |m| render_member_decl(m, indent) }.join
            else render_attribute_decl(member, indent)
            end
          end

          def render_attribute_decl(attr, indent)
            doc = attribute_doc_lines(attr, indent)
            "#{doc}#{indent}attribute :#{attr.name}, #{attr.type_literal}#{attr.attribute_options}\n"
          end

          def attribute_doc_lines(attr, indent)
            doc = attr.documentation
            return "" if doc.nil? || doc.to_s.strip.empty?

            doc.to_s.lines.map { |line| "#{indent}# #{line.strip}\n" }.join
          end

          def class_documentation_lines
            return "" if @documentation.nil? || @documentation.to_s.strip.empty?

            @documentation.to_s.lines.map { |line| "# #{line.strip}\n" }.join
          end

          def render_choice_block(choice, indent)
            inner_indent = indent + (" " * @indent)
            inner = choice.alternatives.map { |alt| render_member_decl(alt, inner_indent) }.join
            "#{indent}#{choice.header} do\n#{inner}#{indent}end\n"
          end

          def imports_lines
            @imports.map { |name| "#{sp}import_model #{name}\n" }.join
          end

          # XML mapping rendering: Sequence wraps its members in
          # `sequence do ... end` (matching XmlCompiler::Sequence). Choice
          # alternatives are emitted at the choice's indent — its members may
          # themselves be Sequences which will then nest.
          def mapping_lines
            @members.map { |m| render_member_mapping(m, sp2) }.join
          end

          def render_member_mapping(member, indent)
            case member
            when Sequence then render_sequence_mapping(member, indent)
            when Choice   then member.alternatives.map { |a| render_member_mapping(a, indent) }.join
            else render_attribute_mapping(member, indent)
            end
          end

          def render_sequence_mapping(sequence, indent)
            inner_indent = indent + (" " * @indent)
            inner = sequence.members.map { |m| render_member_mapping(m, inner_indent) }.join
            "#{indent}sequence do\n#{inner}#{indent}end\n"
          end

          def render_attribute_mapping(attr, indent)
            case attr.kind
            when :element
              "#{indent}map_element \"#{attr.xml_name}\", to: :#{attr.name}\n"
            when :attribute
              "#{indent}map_attribute \"#{attr.xml_name}\", to: :#{attr.name}\n"
            else ""
            end
          end

          def required_files_lines
            return "" if @module_namespace

            lines = dependency_class_names.map do |dep|
              "require_relative \"#{Utils.snake_case(dep)}\""
            end
            lines.empty? ? "" : "#{lines.join("\n")}\n"
          end

        end
      end
    end
  end
end
