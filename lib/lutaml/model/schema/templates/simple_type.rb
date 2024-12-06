# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Templates
        module SimpleType
          extend self
          attr_accessor :simple_types

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { class_name: :String, validations: { pattern: /\+?[0-9]+/ } },
            positiveInteger: { class_name: :Integer, validations: { min: 0 } },
            base64Binary: { class_name: :String, validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedInt: { class_name: :Integer, validations: { min: 0, max: 4294967295 } },
            hexBinary: { class_name: :String, validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            dateTime: { class_name: :DateTime },
            boolean: { class_name: :Boolean },
            integer: { class_name: :Integer },
            string: { class_name: :String },
            token: { class_name: :String, validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            long: { class_name: :Decimal },
            int: { class_name: :Integer }
          }.freeze

          REF_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          class <%= klass_name %> < <%= parent_class %>; end
          TEMPLATE

          MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          class <%= klass_name %> < <%= parent_class %>
            <%= "VALUES = \#{values}" if values_exist = values&.any? -%>

            <%= "LENGTHS = \#{properties[:length]&.map(&:value)}" if length_exist = properties&.key?(:length) -%>

            def self.cast(value)
              value = super(value)<% if pattern_exist = patterns.any? %>
              pattern = <%= patterns.map { |pattern| "(\#{pattern})" }.join('|') %>
              raise_pattern_error(value, pattern) unless value.match?(pattern)<% end %>
              <%= "raise_values_error(value) unless VALUES.include?(value)" if values_exist %>
              <%= "raise_length_error(value) unless LENGTHS.all?(value.length)" if properties&.key?(:length) %>
              <% if min_length_exist = properties[:min_length] -%>
              min_length = <%= min_length_exist %>
              raise_min_length_error(value, min_length) unless value.length >= min_length<% end %>
              <% if max_length_exist = properties[:max_length] %>
              max_length = <%= max_length_exist %>
              raise_max_length_error(value, max_length) unless value.length <= max_length<% end %>
              <% if min_bound_exist = (properties[:min_inclusive] || properties[:min_exclusive]) %>
              min_bound = <%= min_bound_exist %>
              raise_min_bound_error(value, min_bound) unless value <%= properties.key?(:min_inclusive) ? "=>" : ">" %> min_bound<% end %>
              <% if max_bound_exist = (properties[:max_inclusive] || properties[:max_exclusive]) %>
              max_bound = <%= max_bound_exist %>
              raise_max_bound_error(value, max_bound) unless value <%= properties.key?(:max_inclusive) ? "=<" : "<" %> max_bound<% end %>
              value
            end

            <%= "\n  private" if pattern_exist || values_exist || length_exist || min_length_exist || max_length_exist || min_bound_exist || max_bound_exist %>

            <% if pattern_exist %>
            def raise_pattern_error(value, pattern)
              raise Lutaml::Model::InvalidValueError, "The value \#{value} does not match the required pattern: \#{pattern}"
            end<% end %>
            <% if values_exist %>
            def raise_values_error(selected_value)
              raise Lutaml::Model::InvalidValueError, "Invalid value: \"\#{selected_value}\". Allowed values are: \#{VALUES.join(', ')}"
            end<% end %>
            <% if length_exist %>
            def raise_length_error(selected_value)
              raise Lutaml::Model::InvalidValueError, "The provided value \"\#{selected_value}\" should match the specified lengths: \#{LENGTHS.join(',')}"
            end<% end %>
            <% if min_length_exist %>
            def raise_min_length_error(selected_value, min_length)
              raise Lutaml::Model::InvalidValueError, "The provided value \"\#{selected_value}\" has fewer characters than the minimum allowed \#{min_length}"
            end<% end %>
            <% if max_length_exist %>
            def raise_max_length_error(selected_value, max_length)
              raise Lutaml::Model::InvalidValueError, "The provided value \"\#{selected_value}\" exceeds the maximum allowed length of \#{max_length}"
            end<% end %>
            <% if min_bound_exist %>
            def raise_min_bound_error(selected_value, min_bound)
              raise Lutaml::Model::InvalidValueError, "The provided value \"\#{selected_value}\" is less than the minimum allowed value of \#{min_bound}"
            end<% end %>
            <% if max_bound_exist %>
            def raise_max_bound_error(selected_value, max_bound)
              raise Lutaml::Model::InvalidValueError, "The provided value \"\#{selected_value}\" exceeds the maximum allowed value of \#{max_bound}"
            end<% end %>
          end

          TEMPLATE

          def create_simple_types(simple_types)
            @simple_types = {}
            simple_types.each do |name, properties|
              klass_name = Utils.camel_case(name)
              if @simple_types.key?(properties[:base_class])
                parent_class = properties.base_class
                @simple_types[name] = REF_TEMPLATE.result(binding)
                next
              end

              properties.delete(:union) if properties&.key_exist?(:union)
              next if properties.none?

              base_class = properties.base_class.split(":")&.last&.to_sym
              if SUPPORTED_DATA_TYPES.key?(base_class)
                supported_hash = SUPPORTED_DATA_TYPES[base_class]
                parent_class = "Lutaml::Model::Type::#{supported_hash[:class_name]}"
                validations = supported_hash[:validations]
              end
              values = properties[:values]
              patterns = [properties[:pattern], validations&.dig(:pattern)].compact
              @simple_types[name] = MODEL_TEMPLATE.result(binding)
            end
            @simple_types
          end
        end
      end
    end
  end
end
