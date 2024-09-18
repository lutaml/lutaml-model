module Lutaml
  module Model
    class MappingHash < Hash
      attr_accessor :ordered

      def initialize
        @ordered = false
        @item_order = []

        super
      end

      def item_order
        @item_order&.map { |key| normalize(key) } || keys
      end

      def item_order=(order)
        raise "`item order` must be an array" unless order.is_a?(Array)

        @item_order = order
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
