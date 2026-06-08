# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders the attribute-declaration block of a generated class:
        # the lines between `class X < Parent` and `xml do`. Used by
        # Renderers::Model.
        class MemberDecls
          def self.render(members, indent:, base_indent:, mixed: false,
                          text_content: false, simple_content: nil,
                          attribute_directives: [])
            new(indent: indent, base_indent: base_indent,
                mixed: mixed,
                text_content: text_content,
                simple_content: simple_content,
                attribute_directives: attribute_directives).render(members)
          end

          def initialize(indent:, base_indent:, mixed:, text_content:,
                         simple_content:, attribute_directives:)
            @indent = indent
            @base_indent = base_indent
            @mixed = mixed
            @text_content = text_content
            @simple_content = simple_content
            @attribute_directives = attribute_directives
          end

          def render(members)
            lines = members.map { |m| render_one(m, @indent) }.join
            lines + content_attribute_line + simple_content_extras + directive_lines
          end

          private

          def render_one(member, indent)
            case member
            when Definitions::Choice      then render_choice(member, indent)
            when Definitions::Sequence    then member.members.map { |m| render_one(m, indent) }.join
            when Definitions::Attribute   then render_attribute(member, indent)
            when Definitions::GroupImport then "#{indent}import_model_attributes :#{member.name}\n"
            end
          end

          def render_choice(choice, indent)
            inner_indent = indent + @base_indent
            inner = choice.alternatives.map { |alt| render_one(alt, inner_indent) }.join
            "#{indent}#{choice.header} do\n#{inner}#{indent}end\n"
          end

          def render_attribute(attr, indent)
            doc = format_doc(attr.documentation, indent)
            "#{doc}#{indent}attribute :#{attr.name}, #{type_literal(attr.type)}#{options_suffix(attr)}\n"
          end

          def format_doc(doc, indent)
            return "" if Utils.blank?(doc&.to_s&.strip)

            doc.to_s.lines.map { |line| "#{indent}# #{line.strip}\n" }.join
          end

          def type_literal(type_ref)
            case type_ref.kind
            when :symbol    then ":#{type_ref.value}"
            when :class_ref then type_ref.value
            when :w3c       then "::#{type_ref.value}"
            end
          end

          def options_suffix(attr)
            opts = []
            opts << collection_option(attr.collection) if attr.collection
            opts << "default: -> { #{attr.default.inspect} }" if attr.default
            opts << "initialize_empty: true" if attr.initialize_empty
            opts.empty? ? "" : ", #{opts.join(', ')}"
          end

          def collection_option(coll)
            case coll
            when true  then "collection: true"
            when Range then range_option(coll)
            end
          end

          def range_option(range)
            ending = if range.end&.respond_to?(:infinite?) && range.end.infinite?
                       "Float::INFINITY"
                     else
                       range.end
                     end
            "collection: #{range.begin}..#{ending}"
          end

          def content_attribute_line
            return simple_content_attribute if @simple_content
            return "#{@indent}attribute :content, :string, collection: true\n" if @mixed
            return "#{@indent}attribute :content, :string\n" if @text_content

            ""
          end

          def simple_content_attribute
            type_sym = Utils.snake_case(Utils.last_of_split(@simple_content.base_class))
            "#{@indent}attribute :content, :#{type_sym}\n"
          end

          def simple_content_extras
            return "" unless @simple_content

            @simple_content.additional_attributes.map { |a| render_attribute(a, @indent) }.join
          end

          def directive_lines
            @attribute_directives.map { |line| "#{@indent}#{line}\n" }.join
          end
        end
      end
    end
  end
end
