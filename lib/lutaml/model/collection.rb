require "forwardable"

module Lutaml
  module Model
    class Collection
      include Enumerable
      extend Forwardable

      attr_reader :items

      def_delegators :@items, :each, :<<, :push, :size, :to_s, :to_yaml, :to_json, :empty?, :[], :length, :+, :compact, :first, :last, :join, :to_a, :to_ary

      def initialize(items = [])
        @items = items
      end

      def map(&block)
        self.class.new(@items.map(&block))
      end

      def concat(other)
        case other
        when Array
          @items.concat(other)
        when self.class
          @items.concat(other.items)
        else
          @items.push(other)
        end
        self
      end

      def ==(other)
        case other
        when Array
          @items == other
        when self.class
          @items == other.items
        else
          false
        end
      end

      def collection?
        true
      end
    end
  end
end
