module Lutaml
  module Model
    class Attribute
      attr_reader :name, :type, :options

      def initialize(name, type, options = {})
        @name = name
        @type = cast_type(type)

        @options = options

        if collection? && !options[:default]
          @options[:default] = -> { [] }
        end
      end

      def cast_type(type)
        case type
        when Class
          type
        when String
          Type.const_get(type)
        when Symbol
          Type.const_get(type.to_s.split("_").collect(&:capitalize).join)
        end
      rescue NameError
        raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
      end

      def collection?
        options[:collection] || false
      end

      def default
        return options[:default].call if options[:default].is_a?(Proc)

        options[:default]
      end

      def render_nil?
        options.fetch(:render_nil, false)
      end

      def serialize(value, format, options = {})
        if value.is_a?(Array)
          value.map do |v|
            serialize(v, format, options)
          end
        elsif type <= Serialize
          type.hash_representation(value, format, options)
        else
          type.serialize(value)
        end
      end

      def cast(value, format, options = {})
        value ||= [] if collection?
        instance = options[:instance]

        if value.is_a?(Array)
          value.map do |v|
            cast(v, format, instance: instance)
          end
        elsif type <= Serialize
          instance ||= type.model.new
          type.apply_mappings(value, format, instance, options)
          instance
        else
          Lutaml::Model::Type.cast(value, type)
        end
      end
    end
  end
end
