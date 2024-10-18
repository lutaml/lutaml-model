require_relative "xml_mapping_rule"

module Lutaml
  module Model
    class XmlGroupMapping
      attr_reader :elements,
                  :attributes,
                  :content

      def initialize(from, to)
        @elements = {}
        @attributes = {}
        @content = nil
        @method_from = from
        @method_to = to
        @group = "group_#{hash}"
      end

      # def map_element(element, namespace: :undefined, prefix: :undefined)
      #   using = { from: @method_from, to: @method_to }

      #   rule = XmlMappingRule.new(
      #     element,
      #     namespace: namespace,
      #     prefix: prefix,
      #     namespace_set: namespace_set != false,
      #     prefix_set: prefix_set != false,
      #     methods: using,
      #     group: @group
      #   )
      #   @elements[rule.namespaced_name] = rule
      # end

      # def map_attribute(attribute, namespace: nil, prefix: nil)
      #   # attribute,
      #   # using: { from: @from, to: @to },
      #   # group: @name,
      #   # namespace: namespace,
      #   # prefix: prefix
      # end

      # def map_content
      #   # using: { from: @from, to: @to }, group: @name
      # end
    end
  end
end
