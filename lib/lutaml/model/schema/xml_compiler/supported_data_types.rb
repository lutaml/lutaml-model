# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD built-in type table. Keys are the XSD type names; values
        # describe how to render the generated subclass.
        # `skippable: true` means the XSD type maps directly to a
        # Lutaml primitive symbol and needs no generated class.
        module SupportedDataTypes
          TC = Lutaml::Model::Type::TYPE_CODES

          TABLE = {
            nonNegativeInteger: { skippable: false, class_name: TC[:string],
                                  validations: { pattern: /\+?[0-9]+/ } },
            normalizedString: { skippable: false, class_name: TC[:string],
                                validations: { transform: "value.gsub(/[\\r\\n\\t]/, ' ')" } },
            positiveInteger: { skippable: false, class_name: TC[:integer],
                               validations: { min_inclusive: 0 } },
            unsignedShort: { skippable: false, class_name: TC[:integer],
                             validations: { min_inclusive: 0, max_inclusive: 65535 } },
            base64Binary: { skippable: false, class_name: TC[:string],
                            validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { skippable: false, class_name: TC[:integer],
                            validations: { min_inclusive: 0, max_inclusive: 18446744073709551615 } },
            unsignedByte: { skippable: false, class_name: TC[:integer],
                            validations: { min_inclusive: 0, max_inclusive: 255 } },
            unsignedInt: { skippable: false, class_name: TC[:integer],
                           validations: { min_inclusive: 0, max_inclusive: 4294967295 } },
            hexBinary: { skippable: false, class_name: TC[:string],
                         validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            language: { skippable: false, class_name: TC[:string],
                        validations: { pattern: /\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/ } },
            dateTime: { skippable: true, class_name: TC[:date_time] },
            boolean: { skippable: true, class_name: TC[:boolean] },
            integer: { skippable: true, class_name: TC[:integer] },
            decimal: { skippable: true, class_name: TC[:decimal] },
            string: { skippable: true, class_name: TC[:string] },
            double: { skippable: true, class_name: TC[:float] },
            NCName: { skippable: false, class_name: TC[:string],
                      validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
            anyURI: { skippable: false, class_name: TC[:string],
                      validations: { pattern: "\\A\#{URI::DEFAULT_PARSER.make_regexp(%w[http https ftp])}\\z" } },
            token: { skippable: false, class_name: TC[:string],
                     validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            byte: { skippable: false, class_name: TC[:integer],
                    validations: { min_inclusive: -128, max_inclusive: 127 } },
            long: { skippable: false, class_name: TC[:decimal] },
            int: { skippable: true, class_name: TC[:integer] },
            id: { skippable: false, class_name: TC[:string],
                  validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          module_function

          # XSD-name lookup (`SupportedDataTypes[:dateTime]`).
          def [](name)
            TABLE[name]
          end

          def each(&)
            TABLE.each(&)
          end

          # `TypeRef.value` and `simple_content.base_class` ask the same
          # "is this a built-in primitive?" question but pass two different
          # spellings: `simple_content` keeps the XSD name (`"dateTime"`),
          # while attribute TypeRefs store the snake_case rendering
          # (`"date_time"`). Precompute both spellings so neither caller
          # has to know which form the other uses.
          SKIPPABLE_NAMES = TABLE
            .select { |_, info| info[:skippable] }
            .flat_map { |name, _| [name.to_s, Utils.snake_case(name.to_s)] }
            .uniq.freeze

          # True when the XSD type maps to a Lutaml primitive symbol that
          # doesn't need a generated subclass. Accepts XSD-spelled
          # (`"dateTime"`) or snake_case (`"date_time"`) input.
          def skippable?(value)
            SKIPPABLE_NAMES.include?(value.to_s)
          end
        end
      end
    end
  end
end
