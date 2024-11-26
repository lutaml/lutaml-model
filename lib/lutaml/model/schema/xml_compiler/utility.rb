# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        module Utility
          def resolved_element_order(object, ignore_text: true)
            object.element_order.each_with_object(object.element_order.dup) do |name, array|
              next array.delete(name) if name == "text" && (ignore_text || !object.respond_to?(:text))

              index = 0
              array.each_with_index do |element, i|
                next unless element == name

                array[i] = object.send(Utils.snake_case(name))[index]
                index += 1
              end
            end
          end
        end
      end
    end
  end
end
