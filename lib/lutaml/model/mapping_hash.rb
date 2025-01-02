module Lutaml
  module Model
    class MappingHash < Hash
      attr_accessor :ordered, :node

      def initialize
        @ordered = false
        @item_order = []

        super
      end

      def item_order
        @item_order&.map { |key| normalize(key) } || keys
      end

      def fetch(rule, options)
        attr_name = rule.namespaced_name(options[:default_namespace])

        if rule.attribute?
          self["attributes"][attr_name]
        else
          self["elements"][attr_name]
        end
      end

      # def fetch(rule, options)
      #   binding.irb
      #   attr_name = rule.namespaced_name(options[:default_namespace])

      #   if rule.attribute?
      #     return self["attributes"][attr_name]
      #   end

      #   element = self["elements"][attr_name]

      #   if element.is_a?(Hash) && (element["elements"])
      #     binding.irb
      #     element["attributes"].delete_if { |_, value| value.empty? }
      #     element["elements"].delete_if { |_, value| value.empty? }
      #   else
      #     element
      #   end
      # end

      # def fetch(rule, options)
      #   binding.irb
      #   attr_name = rule.namespaced_name(options[:default_namespace])

      #   if rule.attribute?
      #     return self["attributes"][attr_name]
      #   end

      #   element = self["elements"][attr_name]
      #   return nil unless element

      #   if element.is_a?(Hash) && (element["elements"] || element["attributes"])
      #     binding.irb
      #     return element.delete_if { |el| el["attributes"].empty? }

      #     element["elements"] unless element["elements"].empty?
      #   else
      #     return element
      #   end
      # end

      def key_exist_for_rule?(rule, options)
        attr_name = rule.namespaced_name(options[:default_namespace])
        if rule.attribute?
          self["attributes"].key?(attr_name)
        else
          self["elements"].key?(attr_name)
        end
      end

      def item_order=(order)
        raise "`item order` must be an array" unless order.is_a?(Array)

        @item_order = order
      end

      def text
        self["elements"]["#cdata-section"] || self["elements"]["text"]
      end

      def text?
        key?("#cdata-section") || key?("text")
      end

      def content_key(rule)
        rule.cdata ? self["elements"]["#cdata-section"] : self["elements"]["text"]
      end

      def ordered?
        @ordered
      end

      def method_missing(method_name, *args)
        value = self[method_name] || self[method_name.to_s]
        return value if value

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        key_present = key?(method_name) || key?(method_name.to_s)
        return true if key_present

        super
      end

      private

      def normalize(key)
        if self[key.to_s]
          key.to_s
        elsif self[key.to_sym]
          key.to_sym
        else
          key
        end
      end
    end
  end
end
