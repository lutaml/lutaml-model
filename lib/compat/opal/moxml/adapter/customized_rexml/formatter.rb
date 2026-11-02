# frozen_string_literal: true

require "rexml/formatters/pretty"

module Moxml
  module Adapter
    module CustomizedRexml
      # Custom REXML formatter that fixes indentation and wrapping issues
      class Formatter < ::REXML::Formatters::Pretty
        def initialize(indentation: 2, self_close_empty: false, adapter: nil)
          @indentation = " " * indentation
          @level = 0
          @compact = true
          @width = -1 # Disable line wrapping
          @self_close_empty = self_close_empty
          @adapter = adapter
        end

        def write(node, output)
          case node
          when ::REXML::XMLDecl
            write_declaration(node, output)
          when ::Moxml::Adapter::CustomizedRexml::EntityReference
            output << "&#{node.name};"
          else
            super
          end
        end

        def indented?
          !@indentation.empty?
        end

        def write_element(node, output)
          output << "<#{node.expanded_name}"
          write_attributes(node, output)

          # Check for entity refs stored in adapter attachments
          entity_refs = @adapter&.attachments&.get(node, :entity_refs)
          child_sequence = @adapter&.attachments&.get(node, :child_sequence)

          has_no_children = node.children.empty? && !(entity_refs && !entity_refs.empty?)

          if has_no_children && @self_close_empty
            output << "/>"
            return
          end

          output << ">"

          has_text = node.children.any? { |c| c.is_a?(::REXML::Text) && !c.to_s.strip.empty? }
          has_elements = node.children.any?(::REXML::Element)
          indent_children = indented? && has_elements && !has_text

          # Handle children based on content type
          all_children_empty = node.children.empty? && !(entity_refs && !entity_refs.empty?)
          unless all_children_empty
            @level += @indentation.length if indent_children

            if entity_refs && !entity_refs.empty? && child_sequence
              eref_idx = 0
              native_idx = 0
              child_sequence.each do |type|
                case type
                when :native
                  if native_idx < node.children.size
                    child = node.children[native_idx]
                    native_idx += 1
                    next if child.is_a?(::REXML::Text) &&
                      child.to_s.strip.empty? &&
                      !(child.next_sibling.nil? && child.previous_sibling.nil?)

                    output << "\n" << (" " * @level) if indent_children
                    write(child, output)
                  end
                when :eref
                  if eref_idx < entity_refs.size
                    output << "\n" << (" " * @level) if indent_children
                    write(entity_refs[eref_idx], output)
                    eref_idx += 1
                  end
                end
              end
            else
              node.children.each_with_index do |child, _index|
                next if child.is_a?(::REXML::Text) &&
                  child.to_s.strip.empty? &&
                  !(child.next_sibling.nil? && child.previous_sibling.nil?)

                output << "\n" << (" " * @level) if indent_children
                write(child, output)
              end
            end

            if indent_children
              @level -= @indentation.length
              output << "\n" << (" " * @level)
            end
          end

          output << "</#{node.expanded_name}>"
        end

        def write_text(node, output)
          text = node.value
          return if text.empty?

          output << escape_text(text)
        end

        def escape_text(text)
          text.to_s.gsub(/[<>&]/) do |match|
            case match
            when "<" then "&lt;"
            when ">" then "&gt;"
            when "&" then "&amp;"
            end
          end
        end

        private

        def find_significant_sibling(node, direction)
          method = direction == :next ? :next_sibling : :previous_sibling
          sibling = node.send(method)
          sibling = sibling.send(method) while sibling.is_a?(::REXML::Text) && sibling.to_s.strip.empty?
          sibling
        end

        def write_cdata(node, output)
          # output << ' ' * @level
          output << ::REXML::CData::START
          output << node.to_s.gsub(::REXML::CData::STOP, "]]]]><![CDATA[>")
          output << ::REXML::CData::STOP
          # output << "\n"
        end

        def write_comment(node, output)
          # output << ' ' * @level
          output << "<!--"
          output << node.to_s
          output << "-->"
          # output << "\n"
        end

        def write_instruction(node, output)
          # output << ' ' * @level
          output << "<?"
          output << node.target
          output << " "
          output << node.content if node.content
          output << "?>"
          # output << "\n"
        end

        def write_document(node, output)
          node.children.each do |child|
            write(child, output)
            # output << "\n" unless child == node.children.last
          end
        end

        def write_doctype(node, output)
          output << "<!DOCTYPE "
          output << node.name
          output << " "
          output << node.external_id if node.external_id
          output << ">"
          # output << "\n"
        end

        def write_declaration(node, output)
          output << "<?xml"
          output << %( version="#{node.version}") if node.version
          if node.writeencoding
            output << %( encoding="#{node.encoding.to_s.upcase}")
          end
          output << %( standalone="#{node.standalone}") if node.standalone
          output << "?>"
          # output << "\n"
        end

        def write_attributes(node, output)
          # First write namespace declarations
          node.attributes.each do |name, attr|
            next unless name.to_s.start_with?("xmlns:") || name.to_s == "xmlns"

            name = "xmlns" if name.to_s == "xmlns:"
            value = attr.is_a?(::REXML::Attribute) ? attr.value : attr
            output << " #{name}=\"#{value}\""
          end

          # Then write regular attributes
          node.attributes.each do |name, attr| # rubocop:disable Style/CombinableLoops
            next if name.to_s.start_with?("xmlns:") || name.to_s == "xmlns"

            output << " "
            output << if attr.is_a?(::REXML::Attribute) && attr.prefix
                        "#{attr.prefix}:#{attr.name}"
                      else
                        name.to_s
                      end

            output << "=\""
            value = attr.is_a?(::REXML::Attribute) ? attr.value : attr
            output << escape_attribute_value(value.to_s)
            output << "\""
          end # rubocop:enable Style/CombinableLoops
        end

        def escape_attribute_value(value)
          value.to_s.gsub(/[<>&"]/) do |match|
            case match
            when "<" then "&lt;"
            when ">" then "&gt;"
            when "&" then "&amp;"
            when '"' then "&quot;"
              # when "'" then '&apos;'
            end
          end
        end
      end
    end
  end
end
