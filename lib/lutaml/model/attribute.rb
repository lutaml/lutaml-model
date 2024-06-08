# lib/lutaml/model/attribute.rb
module Lutaml
  module Model
    class Attribute
      attr_reader :name, :type, :options

      def initialize(name, type, options = {})
        @name = name
        @type = type
        @options = options
      end

      def collection?
        options[:collection] || false
      end

      def default
        options[:default].is_a?(Proc) ? options[:default].call : options[:default]
      end

      def render_nil?
        options.fetch(:render_nil, false)
      end
    end
  end
end
