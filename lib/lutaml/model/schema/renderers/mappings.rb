# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders the `map_element` / `map_attribute` / `sequence do` lines
        # inside the `xml do ... end` block of a generated class. Used by
        # Renderers::Model.
        class Mappings
          def self.render(members, indent:, base_indent:)
            new(indent: indent, base_indent: base_indent).render(members)
          end

          def initialize(indent:, base_indent:)
            @indent = indent
            @base_indent = base_indent
          end

          def render(members)
            members.map { |m| render_one(m, @indent) }.join
          end

          private

          def render_one(member, indent)
            case member
            when Definitions::Sequence  then render_sequence(member, indent)
            when Definitions::Choice    then member.alternatives.map { |a| render_one(a, indent) }.join
            when Definitions::Attribute then render_attribute(member, indent)
            end
          end

          def render_sequence(sequence, indent)
            inner_indent = indent + @base_indent
            inner = sequence.members.map { |m| render_one(m, inner_indent) }.join
            "#{indent}sequence do\n#{inner}#{indent}end\n"
          end

          def render_attribute(attr, indent)
            case attr.kind
            when :element   then %(#{indent}map_element "#{attr.xml_name}", to: :#{attr.name}\n)
            when :attribute then %(#{indent}map_attribute "#{attr.xml_name}", to: :#{attr.name}\n)
            else ""
            end
          end
        end
      end
    end
  end
end
