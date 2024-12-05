# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Templates
        module SimpleType
          extend self
          attr_accessor :simple_types

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { class_name: :string, validations: { pattern: /\+?[0-9]+/ } },
            positiveInteger: { class_name: :integer, validations: { min: 0 } },
            base64Binary: { class_name: :string, validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedInt: { class_name: :integer, validations: { min: 0, max: 4294967295 } },
            hexBinary: { class_name: :string, validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            dateTime: { class_name: :date_time },
            boolean: { class_name: :boolean },
            integer: { class_name: :integer },
            string: { class_name: :string },
            token: { class_name: :string, validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            long: { class_name: :decimal },
            int: { class_name: :integer }
          }.freeze

          REF_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true
          class <%= Utils.camel_case(name) %> < <%= parent_class %>; end
          TEMPLATE

          MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          class <%= Utils.camel_case(name) %> < <%= parent_class %>
            def self.cast(value)
              <% validations&.each do |key, validation_value| -%>
                <% if key == :pattern %>
              pattern = <%= validation_value.inspect %>
              unless value.match?(pattern)
                raise Lutaml::Model::InvalidValueError.new(name, value, pattern.inspect)
              end
                <% end -%>
              <% end %>
              value
            end
          end
          TEMPLATE

          def create_simple_types(simple_types)
            @simple_types = {}
            simple_types.each do |name, properties|
              base_class = properties.base_class.split(":")&.last&.to_sym
              if SUPPORTED_DATA_TYPES.key?(base_class)
                supported_hash = SUPPORTED_DATA_TYPES[base_class]
                supported_type = Utils.camel_case(supported_hash[:class_name].to_s)
                parent_class = "Lutaml::Model::Type::#{supported_type}"
                validations = supported_hash[:validations]
              end
              values = properties[:values]
              @simple_types[name] = MODEL_TEMPLATE.result(binding)
            end
            @simple_types
          end
        end
      end
    end
  end
end
