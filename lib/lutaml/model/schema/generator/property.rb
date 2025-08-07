module Lutaml
  module Model
    module Schema
      module Generator
        # This class is used to generate a property schema definition.
        # It is used in the context of generating JSON schemas.
        class Property
          attr_reader :name, :attribute, :__register

          def initialize(name, attribute, register:)
            @name = name.to_s.gsub("::", "_")
            @attribute = attribute
            @__register = register
          end

          def to_schema
            { name => generate_attribute_schema(attribute) }
          end

          private

          def generate_attribute_schema(attr, options = {})
            include_null = options.fetch(:include_null, true)
            inside_collection = options.fetch(:inside_collection, false)
            if attr.collection? && !inside_collection
              collection_schema(attr)
            elsif attr.serializable?(__register) && polymorphic?(attr)
              polymorphic_schema(attr)
            elsif attr.serializable?(__register)
              Generator::Ref.new(attr.type(__register)).to_schema
            else
              primitive_schema(attr, include_null: include_null)
            end
          end

          def collection_schema(attr)
            schema = {
              "type" => "array",
              "items" => generate_attribute_schema(
                attr,
                include_null: false,
                inside_collection: true,
              ),
            }

            if attr.options[:collection].is_a?(Range)
              add_collection_constraints!(schema, attr.options[:collection])
            end

            schema
          end

          def add_collection_constraints!(schema, range)
            schema["minItems"] = range.begin
            schema["maxItems"] = range.end if range.end
          end

          def polymorphic_schema(attr)
            ref_schemas = attr.options[:polymorphic].map do |type|
              Ref.new(type).to_schema
            end

            ref_schemas << Ref.new(attr.type).to_schema if attr.type

            {
              "type" => ["object", "null"],
              "oneOf" => ref_schemas,
            }
          end

          def primitive_schema(attr, include_null: true)
            type = get_type(attr.type(__register))
            type = [type, "null"] if include_null

            { "type" => type }.merge(get_constraints(attr))
          end

          def get_constraints(attr)
            constraints = {}

            # Add pattern validation
            constraints["pattern"] = attr.pattern.source if attr.pattern

            # Add default value
            constraints["default"] = attr.default(__register) if attr.default_set?(__register)

            # Add enumeration values
            constraints["enum"] = attr.enum_values if attr.enum?

            constraints
          end

          def polymorphic?(attr)
            Utils.present?(attr.options[:polymorphic])
          end

          def get_type(type)
            {
              Lutaml::Model::Type::String => "string",
              Lutaml::Model::Type::Integer => "integer",
              Lutaml::Model::Type::Boolean => "boolean",
              Lutaml::Model::Type::Float => "number",
              Lutaml::Model::Type::Hash => "object",
            }[type] || "string" # Default to string for unknown types
          end
        end
      end
    end
  end
end
