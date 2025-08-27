require "rexml/formatters/pretty"

module Lutaml
  module Model
    module Xml
      module Rexml
        # Custom REXML formatter that fixes indentation and wrapping issues
        class Formatter < ::REXML::Formatters::Pretty
          def initialize(indentation: 2, self_close_empty: false)
            super()
            @indentation = " " * indentation
            @level = 0
            @compact = true
            @width = -1 # Disable line wrapping
            @self_close_empty = self_close_empty
          end

          def write(node, output)
            case node
            when ::REXML::XMLDecl
              write_declaration(node, output)
            else
              super
            end
          end

          def write_element(node, output)
            output << "<#{node.expanded_name}"
            write_attributes(node, output)

            if node.children.empty? && @self_close_empty
              output << "/>"
              return
            end

            output << ">"

            # Check for mixed content
            has_text = node.children.any? { |c| c.is_a?(::REXML::Text) && !c.to_s.strip.empty? }
            has_elements = node.children.any? { |c| c.is_a?(::REXML::Element) }
            mixed = has_text && has_elements

            # Handle children based on content type
            unless node.children.empty?
              @level += @indentation.length unless mixed

              node.children.each_with_index do |child, _index|
                # Skip insignificant whitespace
                next if child.is_a?(::REXML::Text) &&
                  child.to_s.strip.empty? &&
                  !(child.next_sibling.nil? && child.previous_sibling.nil?)

                write(child, output)
              end

              # Reset indentation for closing tag in non-mixed content
              @level -= @indentation.length unless mixed
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

          def write_cdata(node, output)
            output << "<![CDATA["
            output << node.to_s.gsub("]]>", "]]]]><![CDATA[>")
            output << "]]>"
          end

          def write_comment(node, output)
            output << "<!--"
            output << node.to_s
            output << "-->"
          end

          def write_instruction(node, output)
            output << "<?"
            output << node.target
            output << " "
            output << node.content if node.content
            output << "?>"
          end

          def write_document(node, output)
            node.children.each do |child|
              write(child, output)
            end
          end

          def write_doctype(node, output)
            output << "<!DOCTYPE "
            output << node.name
            output << " "
            output << node.external_id if node.external_id
            output << ">"
          end

          def write_declaration(node, output)
            output << "<?xml"
            output << %( version="#{node.version}") if node.version
            output << %( encoding="#{node.encoding.to_s.upcase}") if node.writeencoding
            output << %( standalone="#{node.standalone}") if node.standalone
            output << "?>"
          end

          def write_attributes(node, output)
            # First write namespace declarations
            node.attributes.each do |name, attr|
              next unless name.to_s.start_with?("xmlns:") || name.to_s == "xmlns"

              name = "xmlns" if name.to_s == "xmlns:" # convert the default namespace
              value = attr.respond_to?(:value) ? attr.value : attr
              output << " #{name}=\"#{value}\""
            end

            # Then write regular attributes
            node.attributes.each do |name, attr|
              next if name.to_s.start_with?("xmlns:") || name.to_s == "xmlns"

              output << " "
              output << if attr.respond_to?(:prefix) && attr.prefix
                          "#{attr.prefix}:#{attr.name}"
                        else
                          name.to_s
                        end

              output << "=\""
              value = attr.respond_to?(:value) ? attr.value : attr
              output << escape_attribute_value(value.to_s)
              output << "\""
            end
          end

          def escape_attribute_value(value)
            value.to_s.gsub(/[<>&"]/) do |match|
              case match
              when "<" then "&lt;"
              when ">" then "&gt;"
              when "&" then "&amp;"
              when '"' then "&quot;"
              end
            end
          end
        end
      end
    end
  end
end
