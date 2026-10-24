module Lutaml
  module Model
    module Schema
      module Generator
        # This class is used to generate a property schema definition.
        # It is used in the context of generating JSON schemas.
        class Property
          attr_reader :name, :attribute, :register

          def initialize(name, attribute, register:)
            @name = name.to_s.gsub("::", "_")
            @attribute = attribute
            @register = register
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
            elsif attr.union?
              union_schema(attr, include_null: include_null)
            elsif attr.serializable?(register) && polymorphic?(attr)
              polymorphic_schema(attr)
            elsif attr.serializable?(register)
              Generator::Ref.new(attr.type(register)).to_schema
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

          # Union: anyOf (valid if the value matches at least one member), not
          # oneOf (which would wrongly demand exactly one). A null branch is
          # added for nullable attributes, mirroring primitive_schema, so an
          # optional union still accepts null.
          def union_schema(attr, include_null: true)
            members = attr.union_member_types.map do |member|
              if member.include?(Lutaml::Model::Serialize)
                Ref.new(member).to_schema
              else
                { "type" => get_type(member) }
              end
            end
            members << { "type" => "null" } if include_null
            { "anyOf" => members }.merge(get_constraints(attr))
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
            type = get_type(attr.type(register))
            type = [type, "null"] if include_null

            { "type" => type }.merge(get_constraints(attr))
          end

          def get_constraints(attr)
            constraints = {}

            # Add pattern validation (attribute option conjunctive with the
            # resolved type's restriction facets; a single JSON Schema
            # pattern cannot express conjunction, mirroring the XSD emitter)
            patterns = constraint_patterns(attr)
            if patterns.size > 1
              raise Lutaml::Model::Error,
                    "Cannot export #{patterns.size} conjunctive patterns on " \
                    "#{attr.name} to a single JSON Schema pattern: sibling " \
                    "patterns are alternatives (OR), and JSON Schema cannot " \
                    "express conjunction (AND) without allOf, which is not " \
                    "yet supported."
            end
            # Attribute-option patterns export verbatim (author contract);
            # type-facet patterns carry Ruby \A/\z anchoring, which ECMA
            # regexes lack — express the full-match intent with ^...$.
            if (pattern, from_facet = patterns.first)
              constraints["pattern"] =
                from_facet ? json_schema_pattern(pattern) : pattern.source
            end

            # Add the resolved type's restriction facets and format
            type = attr.type(register)
            if type.is_a?(Class) && type <= Lutaml::Model::Type::Value
              facets = type.facets
              constraints["minimum"] = facets[:min_inclusive] if facets[:min_inclusive]
              constraints["maximum"] = facets[:max_inclusive] if facets[:max_inclusive]
              constraints["exclusiveMinimum"] = facets[:min_exclusive] if facets[:min_exclusive]
              constraints["exclusiveMaximum"] = facets[:max_exclusive] if facets[:max_exclusive]
            end

            # Add default value
            resolved = attr.default_value(register, nil)
            unless Lutaml::Model::Utils.uninitialized?(resolved)
              constraints["default"] = attr.cast_value(resolved, register)
            end

            # Add enumeration values
            constraints["enum"] = attr.enum_values if attr.enum?

            # Add the format keyword for types that declare one (e.g. the
            # NIST Metaschema types: ipv4, ipv6, email, uri-reference)
            format = type.json_schema_format if type.is_a?(Class) &&
              type <= Lutaml::Model::Type::Value
            constraints["format"] = format if format

            constraints
          end

          def constraint_patterns(attr)
            patterns = []
            patterns << [attr.pattern, false] if attr.pattern
            type = attr.type(register)
            if type.is_a?(Class) && type <= Lutaml::Model::Type::Value
              type.facets[:pattern].to_a.each { |re| patterns << [re, true] }
            end
            patterns
          end

          # JSON Schema (ECMA) regexes have no \A/\z; full-match intent is
          # expressed with ^...$ anchoring (the NIST JSON forms do the same).
          def json_schema_pattern(regexp)
            source = regexp.source
            source = source.delete_prefix('\\A').delete_suffix('\\z')
            "^#{source}$"
          end

          def polymorphic?(attr)
            Utils.present?(attr.options[:polymorphic])
          end

          def get_type(type)
            return "integer" if type.is_a?(Class) && type <= Lutaml::Model::Type::Integer
            return "boolean" if type.is_a?(Class) && type <= Lutaml::Model::Type::Boolean
            return "number" if type.is_a?(Class) && type <= Lutaml::Model::Type::Float
            return "number" if type.is_a?(Class) && type <= Lutaml::Model::Type::Decimal
            return "object" if type.is_a?(Class) && type <= Lutaml::Model::Type::Hash

            "string" # Strings and all other scalar types
          end
        end
      end
    end
  end
end
