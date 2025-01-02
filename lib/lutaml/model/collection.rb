module Lutaml
  module Model
    class Collection
      include Enumerable
      attr_reader :items

      def initialize(items = [])
        @items = items
      end

      def map(&block)
        self.class.new(@items.map(&block))
      end

      def each(&block)
        @items.each(&block)
      end

      def <<(item)
        @items << item
        self
      end

      def push(item)
        self << (item)
      end

      def +(other)
        self.class.new(@items + other.to_a)
      end

      def to_a
        @items
      end

      def compact
        self.class.new(@items.compact)
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

      def size
        @items.size
      end

      def [](index)
        @items[index]
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

      def to_s
        @items.to_s
      end

      def to_json(*_args)
        @items.to_json
      end

      def to_yaml
        @items.to_yaml
      end

      def empty?
        @items.empty?
      end

      def first(many = nil)
        many ? @items.first(many) : @items.first
      end

      def last(many = nil)
        many ? @items.last(many) : @items.last
      end

      def join(separator = nil)
        @items.join(separator)
      end

      alias_method :length, :size
    end
  end
end
