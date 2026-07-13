# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders the `map_element` / `map_attribute` / `sequence do` lines
        # inside the `xml do ... end` block of a generated class. Used by
        # Renderers::Model.
        class Mappings
          def self.render(members, indent:, base_indent:, simple_content: nil)
            new(indent: indent, base_indent: base_indent,
                simple_content: simple_content).render(members)
          end

          def initialize(indent:, base_indent:, simple_content:)
            @indent = indent
            @base_indent = base_indent
            @simple_content = simple_content
          end

          def render(members)
            members.map { |m| render_one(m, @indent) }.join +
              simple_content_attribute_mappings
          end

          private

          def render_one(member, indent)
            case member
            when Definitions::Sequence    then render_sequence(member, indent)
            when Definitions::Choice      then member.alternatives.map { |a| render_one(a, indent) }.join
            when Definitions::Attribute   then render_attribute(member, indent)
            when Definitions::GroupImport then "#{indent}import_model_mappings :#{member.name}\n"
            end
          end

          def render_sequence(sequence, indent)
            inner_indent = indent + @base_indent
            inner = sequence.members.map { |m| render_one(m, inner_indent) }.join
            "#{indent}sequence do\n#{inner}#{indent}end\n"
          end

          def render_attribute(attr, indent)
            case attr.kind
            when :element   then map_member("map_element", attr, indent)
            when :attribute then map_member("map_attribute", attr, indent)
            else ""
            end
          end

          def map_member(verb, attr, indent)
            %(#{indent}#{verb} "#{attr.xml_name}", to: :#{attr.name}#{render_options(attr)}\n)
          end

          def render_options(attr)
            opts = []
            opts << "render_default: true" if attr.render_default
            opts << "render_empty: true"   if attr.render_empty
            opts.empty? ? "" : ", #{opts.join(', ')}"
          end

          def simple_content_attribute_mappings
            return "" unless @simple_content

            @simple_content.additional_attributes.map { |a| render_one(a, @indent) }.join
          end
        end
      end
    end
  end
end
