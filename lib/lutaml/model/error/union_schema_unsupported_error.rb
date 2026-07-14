module Lutaml
  module Model
    class UnionSchemaUnsupportedError < Error
      def initialize(attribute, format)
        super("Union-typed attribute `#{attribute}` cannot be exported to " \
              "#{format}; union types are only representable in JSON Schema " \
              "(anyOf).")
      end
    end
  end
end
