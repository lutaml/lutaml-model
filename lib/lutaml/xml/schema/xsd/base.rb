# frozen_string_literal: true

require "canon"

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Base < Lutaml::Model::Serializable
          XML_DECLARATION_REGEX = /<\?xml[^>]+>\s+/
          ELEMENT_ORDER_IGNORABLE = %w[import include].freeze

          def to_formatted_xml(except: [])
            Canon.format_xml(
              to_xml(except: except),
            ).gsub(XML_DECLARATION_REGEX, "")
          end

          def resolved_element_order
            element_order.each_with_object(element_order.dup) do |element, array|
              next delete_deletables(array, element) if deletable?(element)

              update_element_array(array, element)
            end
          end

          # liquid do
          #   map "to_xml", to: :to_xml
          #   map "to_formatted_xml", to: :to_formatted_xml
          #   map "resolved_element_order", to: :resolved_element_order
          # end

          private

          def deletable?(instance)
            instance.text? ||
              ELEMENT_ORDER_IGNORABLE.include?(instance.name)
          end

          def delete_deletables(array, instance)
            array.delete_if { |ins| ins == instance }
          end

          def update_element_array(array, instance)
            index = 0
            array.each_with_index do |element, i|
              next unless element == instance

              method_name = ::Lutaml::Model::Utils.snake_case(instance.name)
              array[i] = Array(send(method_name))[index]
              index += 1
            end
          end
        end
      end
    end
  end
end
