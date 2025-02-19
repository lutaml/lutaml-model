require "forwardable"

module Lutaml
  module Model
    class Collection < Lutaml::Model::Serializable
      include Enumerable
      extend Forwardable

      #attr_reader :items      

      def self.instances(name, type)
        # require 'byebug'; debugger
        attribute(name, type, { collection: true })
      end

      def initialize(items = [], collection_name = "__items", type = nil)
        # require 'byebug'; debugger
        super()
        # binding.irb
        unless self.class < Lutaml::Model::Collection
          instance_variable_set(:"@#{collection_name}", items)
          @collection_name = collection_name
          @type = type

          # require 'byebug'; debugger
          self.class.def_delegators :"@#{@collection_name}", :each, :<<, :push, :size, :to_s, :to_yaml, :to_json, :empty?, :[], :length, :+, :compact, :first, :last, :join, :to_a, :to_ary, :eql?
        end
      end

      def collection_var_name
        instance_variable_get(:"@#{@collection_name}")
      end

      def map(&block)
        self.class.new(collection_var_name.map(&block), @collection_name, @type)
      end

      def concat(other)
        case other
        when Array
          collection_var_name.concat(other)
        when self.class
          collection_var_name.concat(other.items)
        else
          collection_var_name.push(other)
        end
        self
      end

      def ==(other)
        case other
        when Array
          collection_var_name == other
        when self.class
          collection_var_name == other.items
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
