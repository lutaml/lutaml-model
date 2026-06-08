# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # Iteration helper for the Lutaml::Xml XSD AST. Wraps the
        # `#element_order` array each AST node carries with the special
        # cases the compiler relies on:
        #   * built-in `Xsd::Base` nodes already produce a resolved order
        #   * `text`-only entries and `<import>` / `<include>` siblings
        #     are skipped
        #   * placeholders in the order are mapped to the matching child
        #     accessor on the node so callers receive concrete AST values.
        module ElementOrder
          module_function

          def resolved(object)
            return [] if object.element_order.nil?

            if object.is_a?(Lutaml::Xml::Schema::Xsd::Base)
              return object.resolved_element_order
            end

            object.element_order.each_with_object(object.element_order.dup) do |builder, array|
              next array.delete(builder) if builder.text? || ELEMENT_ORDER_IGNORABLE.include?(builder.name)

              index = 0
              array.each_with_index do |element, i|
                next unless element == builder

                array[i] = Array(object.public_send(Utils.snake_case(builder.name)))[index]
                index += 1
              end
            end
            object.element_order
          end
        end
      end
    end
  end
end
