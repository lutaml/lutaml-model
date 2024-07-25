# lib/lutaml/model/type.rb

module Lutaml
  module Model
    class MappingHash < Hash
      attr_accessor :ordered

      def initialize
        @ordered = false
        @item_order = []

        super
      end

      def each_in_order(&block)
        item_order.each do |item|
          pair = [item, self[item]]

          yield(pair)
        end
      end

      def item_order
        @item_order&.map { |key| normalize(key) } || self.keys
      end

      def item_order=(order)
        raise "`item order` must be an array" unless order.is_a?(Array)

        @item_order = order
      end

      def ordered?
        @ordered
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
