# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # RNG GeneratedClass -> Lutaml::Model::Serializable subclass.
        # Inherits the full render flow from
        # Lutaml::Model::Schema::SerializableRenderer; overrides only the
        # RNG-specific hook values.
        #
        # A class is either "rooted" (a concrete XML element) or "fragment"
        # (a type-only model pulled into other classes via `import_model`).
        # Members can be Attribute (a single attribute) or Choice
        # (a `choice do ... end` block listing alternatives).
        class GeneratedClass < Lutaml::Model::Schema::SerializableRenderer
          attr_reader :class_name, :xml_name, :members, :imports
          attr_accessor :mixed, :text_content, :fragment, :documentation,
                        :namespace_class

          def initialize(class_name:, xml_name:, fragment: false,
                         documentation: nil, namespace_class: nil)
            super()
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

          # --- SerializableRenderer overrides ---

          def rendered_class_name
            class_name
          end

          def serializable_class_required_files
            required_files_lines
          end

          def serializable_class_documentation
            class_documentation_lines
          end

          def serializable_class_attributes
            member_lines
          end

          def serializable_class_imports
            imports_lines
          end

          def xml_root_directive_line
            return nil if fragment

            %(element "#{xml_name}")
          end

          def xml_namespace_line
            namespace_class && "namespace #{namespace_class}"
          end

          def xml_mixed_content?
            !!mixed
          end

          def xml_text_content?
            !!text_content
          end

          def xml_attribute_mappings
            mapping_lines
          end

          private

          def sp
            @indent
          end

          def sp2
            @indent * 2
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
            inner_indent = indent + @indent
            inner = choice.alternatives.map { |alt| render_member_decl(alt, inner_indent) }.join
            "#{indent}#{choice.header} do\n#{inner}#{indent}end\n"
          end

          def imports_lines
            @imports.map { |name| "#{sp}import_model #{name}\n" }.join
          end

          # XML mapping rendering: Sequence wraps its members in
          # `sequence do ... end` (matching XmlCompiler::Sequence). Choice
          # alternatives are emitted at the choice's indent — its members
          # may themselves be Sequences which will then nest.
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
            inner_indent = indent + @indent
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
