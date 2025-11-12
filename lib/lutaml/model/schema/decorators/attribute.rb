# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Decorators
        class Attribute
          ATTRIBUTE_TYPES = {
            "string" => ":string",
            "integer" => ":integer",
            "boolean" => ":boolean",
            "number" => ":float",
            "object" => ":hash",
          }.freeze

          attr_reader :name, :options, :polymorphic
          attr_accessor :type, :base_class

          # @param attribute [Hash] The JSON schema attribute to be decorated.
          def initialize(name, options)
            @name = name
            @options = options
            @type = extract_type(options)
            @polymorphic = options["oneOf"]&.map do |choice|
              choice["$ref"].split("/").last
            end
          end

          def default
            @options["default"]
          end

          def polymorphic?
            !!@polymorphic
          end

          def polymorphic_classes
            return [] unless polymorphic?

            @base_class.sub_classes.map do |klass|
              klass.namespaced_name.gsub("_", "::")
            end
          end

          def collection?
            @options["type"] == "array"
          end

          def collection
            return unless collection?

            if @options["minItems"] && @options["maxItems"]
              @options["minItems"]..@options["maxItems"]
            elsif @options["minItems"]
              @options["minItems"]..Float::INFINITY
            elsif @options["maxItems"]
              0..@options["maxItems"]
            else
              true
            end
          end

          def choice?
            false
          end

          private

          def lutaml_type_symbol(type)
            return ":string" if type.nil?

            type = type.first if type.is_a?(Array)

            return array_type(options) if type == "array"
            return object_type(options) if type == "object"

            ATTRIBUTE_TYPES[type] || ":string"
          end

          def array_type(options)
            lutaml_type_symbol(options["items"]["type"])
          end

          def extract_type(options)
            return extract_type(options["items"]) if options["type"] == "array"

            if options["type"]
              lutaml_type_symbol(options["type"])
            elsif options["$ref"]
              options["$ref"].split("/").last.gsub("_", "::")
            else
              ":string" # Default to string if type is not recognized
            end
          end

          def object_type(options)
            if options["oneOf"]
              {
                "polymorphic" => options["oneOf"].map do |choice|
                  choice["$ref"].split("/").last.gsub("_", "::")
                end,
              }

            elsif options["properties"]
              options["properties"].map do |name, attr|
                Attribute.new(name, attr)
              end
            else
              ":hash" # Default to hash if no specific type is defined
            end
          end
        end
      end
    end
  end
end
