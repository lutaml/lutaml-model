# frozen_string_literal: true

require 'erb'
require 'lutaml/xsd'
require_relative './xml_compiler/group'
require_relative './xml_compiler/utility'

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        include Utility
        extend self

        MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: '-')
          # frozen_string_literal: true

          <%- indent = '  ' * type.modules.length -%>
          <%= indent %>class <%= Utils.classify(type.root_name) %> < Lutaml::Model::Serializable
            <%- type.properties.select(&:content?).each do |property| -%>
            <%= indent %>attribute :<%= property.attribute_name %>, <%= property.type.name -%>
            <%- if property.collection? %>, collection: true<% end -%>
            <%- unless property.default.nil? %>, default: -> { <%= property.default %> }<% end %>
            <%- end -%>
            <%- type.properties.select(&:attribute?).each do |property| -%>
            <%= indent %>attribute :<%= property.attribute_name %>, <%= property.type.name -%>
            <%- if property.collection? %>, collection: true<% end -%>
            <%- unless property.default.nil? %>, default: -> { <%= property.default %> }<% end %>
            <%- end -%>
            <%- type.properties.select(&:element?).each do |property| -%>
            <%= indent %>attribute :<%= property.attribute_name %>, <%= property.type.name -%>
            <%- if property.collection? %>, collection: true<% end -%>
            <%- unless property.default.nil? %>, default: -> { <%= property.default %> }<% end %>
            <%- end -%>

            <%- prefix = type.namespace.end_with?('math') ? 'm' : "w" -%>
            <%= indent %>xml do
              <%= indent %>root '<%= type.root %>'
              <%- if type.namespace -%>
              <%= indent %>namespace '<%= type.namespace %>', '<%= prefix %>'
              <%- end -%>
              <%- unless type.properties.empty? -%>

              <%- type.properties.select(&:content?).each do |property| -%>
              <%= indent %>map_content to: :<%= property.attribute_name %>
              <%- end -%>
              <%- type.properties.select(&:attribute?).each do |property| -%>
              <%= indent %>map_attribute '<%= property.mapping_name %>', to: :<%= property.attribute_name -%>
              <%- if property.namespace %>, prefix: '<%= prefix %>'<%- end -%>
              <%- if property.namespace %>, namespace: '<%= property.namespace %>'<% end %>
              <%- end -%>
              <%- type.properties.select(&:element?).each do |property| -%>
              <%= indent %>map_element '<%= property.mapping_name %>', to: :<%= property.attribute_name -%>
              <%- if type.namespace != property.namespace %>, prefix: <%= "'\#{prefix}'" %><%- end -%>
              <%- if type.namespace != property.namespace %>, namespace: <%= property.namespace ? "'\#{property.namespace}'" : 'nil' %><% end %>
              <%- end -%>
              <%- end -%>
            <%= indent %>end
          <%= indent %>end
        TEMPLATE

        XML_ADAPTER_NOT_SET_MESSAGE = <<~MSG
          Nokogiri is not set as XML Adapter.
          Make sure Nokogiri is installed and set as XML Adapter eg. execute:
          gem install nokogiri
          require 'lutaml/model/adapter/nokogiri'
          Lutaml::Model.xml_adapter = Lutaml::Model::Adapter::Nokogiri
        MSG

        IMPORT_CLASSES = [Lutaml::Xsd::Import, Lutaml::Xsd::Include].freeze

        SUPPORTED_DATA_TYPES = {
          unsignedInt: :integer,
          integer: :integer,
          boolean: :boolean,
          string: :string
        }.freeze

        def as_models(schema, options: {})
          unless Lutaml::Model::Config.xml_adapter ||
                 Lutaml::Model::Config.xml_adapter.name.end_with?('NokogiriAdapter')

            raise Error, XML_ADAPTER_NOT_SET_MESSAGE
          end

          parsed_schema = Lutaml::Xsd.parse(schema, location: options[:location])

          @group_types = Lutaml::Model::MappingHash.new
          @simple_types = Lutaml::Model::MappingHash.new
          @complex_types = Lutaml::Model::MappingHash.new

          schema_to_models([parsed_schema])
        end

        def to_models(schemas, options: {})
          types = as_models(schemas, options: options)

          types.to_h do |type|
            [type.file_name, MODEL_TEMPLATE.result(binding)]
          end
        end

        private

        def schema_to_models(schemas)
          return if schemas.empty?

          schemas.each do |schema|
            schema_to_models(schema.schemas) if schema.schemas.any?

            resolved_element_order(schema).each do |order_item|
              next if IMPORT_CLASSES.include?(order_item.class)

              item_name = order_item.name
              case order_item
              when Lutaml::Xsd::SimpleType
                @simple_types[item_name] = setup_simple_type(order_item)
              when Lutaml::Xsd::Group
                @group_types[item_name] = Group.new(order_item).resolve_with(binding)
              when Lutaml::Xsd::ComplexType
                @complex_types[item_name] = setup_complex_type(order_item)
              end
            end
          end
        end

        def setup_simple_type(simple_type)
          Lutaml::Model::MappingHash.new do |hash|
            if simple_type&.restriction&.any?
              restriction = simple_type.restriction.first
              hash[:base_class] = restriction.base&.split(':')&.last
              restriction_content(hash, restriction)
            end
          end
        end

        def restriction_content(hash, restriction)
          hash[:max_length] = restriction.max_length.value if restriction.max_length
          min_max_values(hash, restriction) if min_and_max?(restriction)

          if valid_enumeration?(restriction)
            hash[:enumeration_values] = restriction.enumeration.map(&:value)
          end
        end

        def min_and_max?(restriction)
          restriction.min_inclusive && restriction.max_inclusive
        end

        def min_max_values(hash, restriction)
          case hash[:base_class]
          when "integer", "unsignedInt"
            hash[:min_value] = restriction.min_inclusive.value.to_i
            hash[:max_value] = restriction.max_inclusive.value.to_i
          else
            hash[:min_value] = restriction.min_inclusive.value
            hash[:max_value] = restriction.max_inclusive.value
          end
        end

        def valid_enumeration?(restriction)
          restriction.enumeration.is_a?(Array) &&
            restriction.enumeration.any?
        end

        def setup_complex_type(complex_type)
          Lutaml::Model::MappingHash.new.tap do |hash|
            if complex_type.attribute.any?
              hash[:attributes] = complex_type.attribute.map do |attribute|
                Lutaml::Model::MappingHash.new.tap do |attr_hash|
                  attr_hash[attribute.name] = validate_attr_type(attribute.type)
                end
              end
            elsif complex_type.sequence.any?
              hash[:sequence] = complex_type.sequence.map do |sequence|
                setup_complex_type_sequence(sequence)
              end
            end
          end
        end

        def setup_complex_type_sequence(sequence)
          Lutaml::Model::MappingHash.new do |hash|
            sequence.resolved_element_order.map do |sequence_element|
              # setup_sequence_element(sequence_element)
            end
          end
        end

        def validate_attr_type(type)
          stripped_type = type&.split(':')&.last
          @simple_types[stripped_type] ||
            @complex_types[stripped_type] ||
            SUPPORTED_DATA_TYPES[stripped_type&.to_sym] ||
            stripped_type&.to_sym
        end
      end
    end
  end
end
