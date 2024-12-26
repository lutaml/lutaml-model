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

      # First we make hash with elements and attributes inside, but the issue is when we have nested elements and attributes and 
      # for text we have to check if elements are present inside. This causes the issue. So move to the approach where only attributes separate key
      # and other elements are present as it is in hash. Now facing the mutiple issues.
      def fetch(rule, options)
        # binding.irb
        attr_name = rule.namespaced_name(options[:default_namespace])
        
        if rule.attribute?
          # binding.irb
          if self["attributes"]
            self["attributes"][attr_name]
          else
            self[attr_name]
          end
        else
          # binding.irb
          value = self[attr_name]
          if !value["attributes"].empty?
            value = value["attributes"]
          end
          value
        end
      end

      # def key_exist?(key)
      #   key?(key.to_s) || key?(key.to_sym)
      # end

      def key_exist_for_rule?(rule, options)
        # binding.irb
        attr_name = rule.namespaced_name(options[:default_namespace])
        # if rule.attribute?
        #   key?(attr_name)
        # end
        self.key?(attr_name)
      end

      def item_order=(order)
        raise "`item order` must be an array" unless order.is_a?(Array)

        @item_order = order
      end

      def text
        self["#cdata-section"] || self["text"]
      end

      def text?
        key?("#cdata-section") || key?("text")
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
