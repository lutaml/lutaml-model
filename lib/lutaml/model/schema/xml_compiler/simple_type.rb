# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD simple-type namespace. Holds the SUPPORTED_DATA_TYPES table
        # of XSD built-in types + module-level helpers (`skippable?`,
        # `setup_supported_types`, `setup_restriction`).
        #
        # The actual renderers are two concrete classes:
        #   - XmlCompiler::RestrictedSimpleType  (xs:restriction path)
        #   - XmlCompiler::UnionSimpleType       (xs:union path)
        # XmlCompiler picks one or the other in `setup_simple_type`.
        module SimpleType
          # Shorthand for the canonical lutaml type class strings — avoids
          # duplicating `"Lutaml::Model::Type::X"` literals here when the
          # exact same string lives in Lutaml::Model::Type::TYPE_CODES.
          TC = Lutaml::Model::Type::TYPE_CODES

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { skippable: false,
                                  class_name: TC[:string], validations: { pattern: /\+?[0-9]+/ } },
            normalizedString: { skippable: false,
                                class_name: TC[:string], validations: { transform: "value.gsub(/[\\r\\n\\t]/, ' ')" } },
            positiveInteger: { skippable: false,
                               class_name: TC[:integer], validations: { min_inclusive: 0 } },
            unsignedShort: { skippable: false,
                             class_name: TC[:integer], validations: { min_inclusive: 0, max_inclusive: 65535 } },
            base64Binary: { skippable: false,
                            class_name: TC[:string], validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { skippable: false,
                            class_name: TC[:integer], validations: { min_inclusive: 0, max_inclusive: 18446744073709551615 } },
            unsignedByte: { skippable: false,
                            class_name: TC[:integer], validations: { min_inclusive: 0, max_inclusive: 255 } },
            unsignedInt: { skippable: false,
                           class_name: TC[:integer], validations: { min_inclusive: 0, max_inclusive: 4294967295 } },
            hexBinary: { skippable: false,
                         class_name: TC[:string], validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            language: { skippable: false,
                        class_name: TC[:string], validations: { pattern: /\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/ } },
            dateTime: { skippable: true, class_name: TC[:date_time] },
            boolean: { skippable: true, class_name: TC[:boolean] },
            integer: { skippable: true, class_name: TC[:integer] },
            decimal: { skippable: true, class_name: TC[:decimal] },
            string: { skippable: true, class_name: TC[:string] },
            double: { skippable: true, class_name: TC[:float] },
            NCName: { skippable: false,
                      class_name: TC[:string], validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
            anyURI: { skippable: false,
                      class_name: TC[:string], validations: { pattern: "\\A\#{URI::DEFAULT_PARSER.make_regexp(%w[http https ftp])}\\z" } },
            token: { skippable: false,
                     class_name: TC[:string], validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            byte: { skippable: false,
                    class_name: TC[:integer], validations: { min_inclusive: -128, max_inclusive: 127 } },
            long: { skippable: false, class_name: TC[:decimal] },
            int: { skippable: true, class_name: TC[:integer] },
            id: { skippable: false, class_name: TC[:string],
                  validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          module_function

          # Builds the set of built-in restricted simple-type renderers
          # (e.g. NonNegativeInteger, NormalizedString) keyed by XSD name.
          # Each value is a RestrictedSimpleType ready for rendering.
          def setup_supported_types
            SUPPORTED_DATA_TYPES.reject do |_, simple_type|
              simple_type[:skippable]
            end.each_with_object({}) do |(name, simple_type), hash|
              str_name = name.to_s
              RestrictedSimpleType.new(str_name).tap do |instance|
                instance.base_class = Utils.base_class_snake_case(simple_type[:class_name])
                instance.instance = setup_restriction(instance.base_class,
                                                      simple_type[:validations])
                hash[str_name] = instance
              end
            end
          end

          def setup_restriction(base_class, validations)
            return unless validations

            Restriction.new.tap do |restriction|
              restriction.base_class = base_class
              restriction.min_inclusive = validations[:min_inclusive]
              restriction.max_inclusive = validations[:max_inclusive]
              restriction.pattern = validations[:pattern]
              restriction.transform = validations[:transform]
            end
          end

          def skippable?(type)
            SUPPORTED_DATA_TYPES.dig(type&.to_sym, :skippable)
          end
        end
      end
    end
  end
end
