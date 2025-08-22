# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module LmlCompiler
        class Class
          attr_reader :name, :parent_class, :attributes, :enums, :namespace

          SUPPORTED_TYPES = {
            "string" => "string",
            "integer" => "integer",
            "float" => "float",
            "boolean" => "boolean",
            "date" => "date",
            "date_time" => "date_time",
            "time" => "time",
            "time_without_date" => "time_without_date",
            "decimal" => "decimal",
            "hash" => "hash",
          }.freeze

          COLLECTION_INSTANCES_ATTRIBUTE_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= extended_indent %>instances :<%= attr.name %>, <%= _type_string %><% if attr_collection?(attr) %>, collection: true<% end %><% if attr_required?(attr) %>, required: true<% end %>
          TEMPLATE

          SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= extended_indent %>attribute :<%= attr.name %>, <%= _type_string %><% if is_enum %>, values: <%= _enum_values %><% end %><% if attr_collection?(attr) %>, collection: true<% end %><% if attr_required?(attr) %>, required: true<% end %>
          TEMPLATE

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            <%= required_files %>
            <%= template %>
            <% if namespace %><%= Utils.camel_case(namespace) %>::<% end %><%= Utils.camel_case(name) %>.register_class_with_id
          TEMPLATE

          NAMESPACE_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            module <%= Utils.camel_case(namespace) %>
            <%= class_template %>end
          TEMPLATE

          CLASS_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= @indent %>class <%= Utils.camel_case(name) %> < <%= Utils.camel_case(parent_class_name) %>
            <% attributes.each { |attr| %><%= attribute_template(attr) %><% } if attributes && !attributes.empty? %>
            <%= @indent %>  def self.register
            <%= @indent %>    Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            <%= @indent %>  end

            <%= @indent %>  def self.register_class_with_id
            <%= @indent %>    register.register_model(self, id: :<%= Utils.snake_case(name) %>)
            <%= @indent %>  end
            <%= @indent %>end
          TEMPLATE

          def initialize(klass, enums: [], namespace: nil)
            @name = klass.name
            @parent_class = klass.parent_class
            @attributes = klass.attributes
            @enums = enums.to_h { |enum| [enum.name, enum.attributes.flat_map { |attr| attr.attributes.flat_map(&:type) }] }
            @required_classes = []
            @namespace = namespace
            @indent = ""
          end

          def to_class(options: {})
            TEMPLATE.result(binding)
          end

          private

          def template
            if namespace
              @indent = "  "
              NAMESPACE_TEMPLATE.result(binding)
            else
              class_template
            end
          end

          def class_template
            CLASS_TEMPLATE.result(binding)
          end

          def attribute_template(attr)
            # TODO: Only implemented member_type attribute for collection classes
            return "" if collection_class? && attr.name != "member_type"

            attr_type, is_enum, found_type = resolved_attr_type(attr)
            _type_string = found_type ? ":#{found_type}" : attr_type.to_s
            _enum_values = is_enum ? enums[attr.type] : nil
            if collection_class?
              attr.name = "items"
              COLLECTION_INSTANCES_ATTRIBUTE_TEMPLATE.result(binding)
            else
              SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE.result(binding)
            end
          end

          def enum_type(raw_type)
            values = enums[raw_type]
            return values.first.class.to_s if values && !values.empty?

            "string"
          end

          def required_classes
            return @required_classes unless @required_classes.empty?

            attributes.each do |attr|
              # TODO: Only implemented member_type attribute for collection classes
              next if collection_class? && attr.name != "member_type"

              attr_type, _is_enum, type_found = resolved_attr_type(attr)
              @required_classes << attr_type if type_found.nil?
            end

            @required_classes << parent_class_name unless parent_class_name.start_with?("Lutaml::Model::")

            @required_classes.uniq
          end

          def attr_collection?(attr)
            ["n", "*"].include?(attr.cardinality&.max)
          end

          def attr_required?(attr)
            attr.cardinality&.min.to_i.positive?
          end

          # Helper to resolve attribute type, enum status, and found type
          def resolved_attr_type(attr)
            raw_type = attr.type
            is_enum = enums.key?(raw_type)
            attr_type = is_enum ? enum_type(raw_type) : raw_type
            # TODO: have to define reference to other attributes.
            attr_type = "string" if attr_type.to_s.start_with?("reference:")
            found_type = SUPPORTED_TYPES[attr_type.to_s.downcase]
            [attr_type, is_enum, found_type]
          end

          def required_files
            return "" if required_classes.empty?

            "\n#{required_classes.map { |klass| "require_relative \"#{Utils.snake_case(klass.to_s)}\"\n" }.join}"
          end

          def parent_class_name
            return "Lutaml::Model::Serializable" if parent_class.nil?

            return "Lutaml::Model::Collection" if parent_class == "Array"

            Utils.camel_case(last_of_split(parent_class))
          end

          def collection_class?
            parent_class_name == "Lutaml::Model::Collection"
          end

          def last_of_split(field)
            field&.split(":")&.last
          end

          def extended_indent
            "#{@indent}  "
          end
        end
      end
    end
  end
end
