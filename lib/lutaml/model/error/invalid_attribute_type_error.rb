module Lutaml
  module Model
    class InvalidAttributeTypeError < Error
      def initialize(attr_name, type)
        @attr_name = attr_name
        @value = type

        super()
      end

      def to_s
        "Unsupported type `#{@value}` specified for #{@attr_name}, " \
          "type must inherit Lutaml::Model::Type::Value or Lutaml::Model::Serializable"
      end
    end
  end
end
