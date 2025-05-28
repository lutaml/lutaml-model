# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Choice
          attr_accessor :instances, :min_occurs, :max_occurs

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>choice<%= block_options %> do
            <%= instances.map { |element| element.to_class(indent + INDENT) }.join -%>
            <%= indent %>end
          TEMPLATE

          def initialize
            @instances = []
          end

          def <<(element)
            @instances << element
          end

          def to_class(indent = INDENT)
            TEMPLATE.result(binding)
          end

          private

          def min_option
            "min: #{min_occurs.nil? ? 1 : min_occurs.to_i}"
          end

          def max_option
            value = case max_occurs
                    when "unbounded"
                      "Float::INFINITY"
                    when NilClass
                      1
                    else
                      max_occurs.to_i
                    end
            ", max: #{value}"
          end

          def block_options
            ["(", min_option, max_option, ")"].compact.join
          end
        end
      end
    end
  end
end
