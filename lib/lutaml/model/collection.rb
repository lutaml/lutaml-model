require "forwardable"

module Lutaml
  module Model
    class Collection < Lutaml::Model::Serializable
      include Enumerable
      extend Forwardable

      #attr_reader :items

      def_delegators :@__items, :each, :<<, :push, :size, :to_s, :to_yaml, :to_json, :empty?, :[], :length, :+, :compact, :first, :last, :join, :to_a, :to_ary, :eql?

      def self.instances(name, type)
        # require 'byebug'; debugger
        attribute(name, type, { collection: true })
      end

      def initialize(items = [], collection_name = "@__items", type = nil)
        # require 'byebug'; debugger
        super()
        @__items = items
        @type = type
      end

      def map(&block)
        self.class.new(@__items.map(&block))
      end

      def concat(other)
        case other
        when Array
          @__items.concat(other)
        when self.class
          @__items.concat(other.items)
        else
          @__items.push(other)
        end
        self
      end

      def ==(other)
        case other
        when Array
          @__items == other
        when self.class
          @__items == other.items
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
