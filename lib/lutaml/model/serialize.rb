require_relative "xml_adapter"
require_relative "config"
require_relative "type"
require_relative "attribute"
require_relative "mapping_hash"
require_relative "mapping"
require_relative "json_adapter"
require_relative "comparable_model"
require_relative "schema_location"
require_relative "validation"
require_relative "error"
require_relative "choice"
require_relative "sequence"
require_relative "liquefiable"
require_relative "transform"

module Lutaml
  module Model
    module Serialize
      include ComparableModel
      include Validation
      include Lutaml::Model::Liquefiable

      def self.included(base)
        base.extend(ClassMethods)
        base.initialize_attrs(base)
      end

      module ClassMethods
        include Lutaml::Model::Liquefiable::ClassMethods

        attr_accessor :attributes, :mappings, :choice_attributes

        def inherited(subclass)
          super
          subclass.initialize_attrs(self)
        end

        def included(base)
          base.extend(ClassMethods)
          base.initialize_attrs(self)
        end

        def initialize_attrs(source_class)
          @mappings = Utils.deep_dup(source_class.instance_variable_get(:@mappings)) || {}
          @attributes = Utils.deep_dup(source_class.instance_variable_get(:@attributes)) || {}
          @choice_attributes = Utils.deep_dup(source_class.instance_variable_get(:@choice_attributes)) || []
          instance_variable_set(:@model, self)
        end

        def model(klass = nil)
          if klass
            @model = klass
            add_custom_handling_methods_to_model(klass)
          else
            @model
          end
        end

        def add_custom_handling_methods_to_model(klass)
          Utils.add_boolean_accessor_if_not_defined(klass, :ordered)
          Utils.add_boolean_accessor_if_not_defined(klass, :mixed)
          Utils.add_accessor_if_not_defined(klass, :element_order)
          Utils.add_accessor_if_not_defined(klass, :encoding)

          Utils.add_method_if_not_defined(klass,
                                          :using_default_for) do |attribute_name|
            @using_default ||= {}
            @using_default[attribute_name] = true
          end

          Utils.add_method_if_not_defined(klass,
                                          :value_set_for) do |attribute_name|
            @using_default ||= {}
            @using_default[attribute_name] = false
          end

          Utils.add_method_if_not_defined(klass,
                                          :using_default?) do |attribute_name|
            @using_default ||= {}
            !!@using_default[attribute_name]
          end
        end

        def cast(value)
          value
        end

        def choice(min: 1, max: 1, &block)
          @choice_attributes << Choice.new(self, min, max).tap do |c|
            c.instance_eval(&block)
          end
        end

        # Define an attribute for the model
        def attribute(name, type, options = {})
          if type.is_a?(Hash)
            options[:method_name] = type[:method]
            type = nil
          end

          attr = Attribute.new(name, type, options)
          attributes[name] = attr

          if attr.enum?
            add_enum_methods_to_model(
              model,
              name,
              options[:values],
              collection: options[:collection],
            )
          elsif attr.derived? && name != attr.method_name
            define_method(name) do
              public_send(attr.method_name)
            end
          else
            define_method(name) do
              instance_variable_get(:"@#{name}")
            end

            define_method(:"#{name}=") do |value|
              value_set_for(name)
              instance_variable_set(:"@#{name}", attr.cast_value(value))
            end
          end

          attr
        end

        def root?
          mappings_for(:xml).root?
        end

        def import_model_attributes(model)
          raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

          @attributes.merge!(model.attributes)
        end

        def import_model_mappings(model)
          raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

          @mappings.merge!(model.mappings)
        end

        def import_model(model)
          raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

          import_model_attributes(model)
          import_model_mappings(model)
        end

        def add_enum_methods_to_model(klass, enum_name, values, collection: false)
          add_enum_getter_if_not_defined(klass, enum_name, collection)
          add_enum_setter_if_not_defined(klass, enum_name, values, collection)

          return unless values.all?(::String)

          values.each do |value|
            Utils.add_method_if_not_defined(klass, "#{value}?") do
              curr_value = public_send(:"#{enum_name}")

              if collection
                curr_value.include?(value)
              else
                curr_value == value
              end
            end

            Utils.add_method_if_not_defined(klass, value.to_s) do
              public_send(:"#{value}?")
            end

            Utils.add_method_if_not_defined(klass, "#{value}=") do |val|
              value_set_for(enum_name)
              enum_vals = public_send(:"#{enum_name}")

              enum_vals = if !!val
                            if collection
                              enum_vals << value
                            else
                              [value]
                            end
                          elsif collection
                            enum_vals.delete(value)
                            enum_vals
                          else
                            instance_variable_get(:"@#{enum_name}") - [value]
                          end

              instance_variable_set(:"@#{enum_name}", enum_vals)
            end

            Utils.add_method_if_not_defined(klass, "#{value}!") do
              public_send(:"#{value}=", true)
            end
          end
        end

        def add_enum_getter_if_not_defined(klass, enum_name, collection)
          Utils.add_method_if_not_defined(klass, enum_name) do
            i = instance_variable_get(:"@#{enum_name}") || []

            if !collection && i.is_a?(Array)
              i.first
            else
              i.uniq
            end
          end
        end

        def add_enum_setter_if_not_defined(klass, enum_name, _values, collection)
          Utils.add_method_if_not_defined(klass, "#{enum_name}=") do |value|
            value = [] if value.nil?
            value = [value] if !value.is_a?(Array)

            value_set_for(enum_name)

            if collection
              curr_value = public_send(:"#{enum_name}")

              instance_variable_set(:"@#{enum_name}", curr_value + value)
            else
              instance_variable_set(:"@#{enum_name}", value)
            end
          end
        end

        def enums
          attributes.select { |_, attr| attr.enum? }
        end

        def self.register_format_mapping_method(format)
          define_method(format) do |&block|
            klass = ::Lutaml::Model::FormatRegistry.mappings_class_for(format)
            mappings[format] ||= klass.new

            mappings[format].instance_eval(&block)

            if mappings[format].respond_to?(:finalize)
              mappings[format].finalize(self)
            end
          end
        end

        def self.register_from_format_method(format)
          define_method(:"from_#{format}") do |data, options = {}|
            adapter = Lutaml::Model::FormatRegistry.send(:"#{format}_adapter")

            doc = adapter.parse(data, options)
            public_send(:"of_#{format}", doc, options)
          end

          define_method(:"of_#{format}") do |doc, options = {}|
            if doc.is_a?(Array)
              return doc.map { |item| send(:"of_#{format}", item) }
            end

            if format == :xml
              raise Lutaml::Model::NoRootMappingError.new(self) unless root?

              options[:encoding] = doc.encoding
              # apply_mappings(doc, format, options)
              transformer = Lutaml::Model::FormatRegistry.transformer_for(format)
              transformer.data_to_model(self, doc, :xml, options)
            else
              # apply_mappings(doc.to_h, format)
              transformer = Lutaml::Model::FormatRegistry.transformer_for(format)
              transformer.data_to_model(self, doc, format, options)
            end
          end
        end

        def self.register_to_format_method(format)
          define_method(:"to_#{format}") do |instance, options = {}|
            value = public_send(:"as_#{format}", instance, options)
            adapter = Lutaml::Model::FormatRegistry.public_send(:"#{format}_adapter")

            if format == :xml
              options[:mapper_class] = self
              adapter.new(value).public_send(:"to_#{format}", options)
            else
              adapter.new(value).public_send(:"to_#{format}", options)
            end
          end

          define_method(:"as_#{format}") do |instance, options = {}|
            if instance.is_a?(Array)
              return instance.map { |item| public_send(:"as_#{format}", item) }
            end

            unless instance.is_a?(model)
              msg = "argument is a '#{instance.class}' but should be a '#{model}'"
              raise Lutaml::Model::IncorrectModelError, msg
            end

            transformer = Lutaml::Model::FormatRegistry.transformer_for(format)
            transformer.model_to_data(self, instance, format, options)
          end
        end

        def as(format, instance, options = {})
          public_send(:"as_#{format}", instance, options)
        end

        def to(format, instance, options = {})
          public_send(:"to_#{format}", instance, options)
        end

        def key_value(&block)
          Lutaml::Model::Config::KEY_VALUE_FORMATS.each do |format|
            mappings[format] ||= KeyValueMapping.new(format)
            mappings[format].instance_eval(&block)
          end
        end

        def mappings_for(format)
          mappings[format] || default_mappings(format)
        end

        def default_mappings(format)
          klass = ::Lutaml::Model::FormatRegistry.mappings_class_for(format)
          _mappings = klass.new

          _mappings.tap do |mapping|
            attributes&.each_key do |name|
              mapping.map_element(
                name.to_s,
                to: name,
              )
            end

            mapping.root(to_s.split("::").last) if format == :xml
          end
        end

        def hash_representation(instance, format, options = {})
          Lutaml::Model::KeyValueTransform.model_to_data(self, instance, format, options)
        end

        def apply_mappings(doc, format, options = {})
          instance = options[:instance] || model.new
          return instance if Utils.blank?(doc)

          mappings = mappings_for(format)

          if mappings.polymorphic_mapping
            return resolve_polymorphic(doc, format, mappings, instance, options)
          end

          # options[:mappings] = mappings.mappings
          transformer = Lutaml::Model::FormatRegistry.transformer_for(format)
          transformer.data_to_model(self, doc, format, options)
        end

        def resolve_polymorphic(doc, format, mappings, instance, options = {})
          polymorphic_mapping = mappings.polymorphic_mapping
          return instance if polymorphic_mapping.polymorphic_map.empty?

          klass_key = doc[polymorphic_mapping.name]
          klass_name = polymorphic_mapping.polymorphic_map[klass_key]
          klass = Object.const_get(klass_name)

          klass.apply_mappings(doc, format, options)
        end

        def ensure_utf8(value)
          case value
          when String
            value.encode("UTF-8", invalid: :replace, undef: :replace,
                                  replace: "")
          when Array
            value.map { |v| ensure_utf8(v) }
          when Hash
            value.transform_keys do |k|
              ensure_utf8(k)
            end.transform_values do |v|
              ensure_utf8(v)
            end
          else
            value
          end
        end
      end

      attr_accessor :element_order, :schema_location, :encoding
      attr_writer :ordered, :mixed

      def initialize(attrs = {})
        @using_default = {}
        return unless self.class.attributes

        set_ordering(attrs)
        set_schema_location(attrs)
        initialize_attributes(attrs)
      end

      def attr_value(attrs, name, attr_rule)
        value = if attrs.key?(name.to_sym)
                  attrs[name.to_sym]
                elsif attrs.key?(name.to_s)
                  attrs[name.to_s]
                else
                  attr_rule.default
                end

        if attr_rule.collection? || value.is_a?(Array)
          value&.map do |v|
            if v.is_a?(Hash)
              attr_rule.type.new(v)
            else
              # TODO: This code is problematic because Type.cast does not know
              # about all the types.
              Lutaml::Model::Type.cast(v, attr_rule.type)
            end
          end
        else
          # TODO: This code is problematic because Type.cast does not know
          # about all the types.
          Lutaml::Model::Type.cast(value, attr_rule.type)
        end
      end

      def using_default_for(attribute_name)
        @using_default[attribute_name] = true
      end

      def value_set_for(attribute_name)
        @using_default[attribute_name] = false
      end

      def using_default?(attribute_name)
        @using_default[attribute_name]
      end

      def method_missing(method_name, *args)
        if method_name.to_s.end_with?("=") && self.class.attributes.key?(method_name.to_s.chomp("=").to_sym)
          define_singleton_method(method_name) do |value|
            instance_variable_set(:"@#{method_name.to_s.chomp('=')}", value)
          end
          send(method_name, *args)
        else
          super
        end
      end

      def validate_attribute!(attr_name)
        attr = self.class.attributes[attr_name]
        value = instance_variable_get(:"@#{attr_name}")
        attr.validate_value!(value)
      end

      def ordered?
        !!@ordered
      end

      def mixed?
        !!@mixed
      end

      def key_exist?(hash, key)
        hash.key?(key.to_sym) || hash.key?(key.to_s)
      end

      def key_value(hash, key)
        hash[key.to_sym] || hash[key.to_s]
      end

      def pretty_print_instance_variables
        (instance_variables - %i[@using_default]).sort
      end

      def to_yaml_hash
        self.class.as_yaml(self)
      end

      # TODO: These needs to be dynamic
      # def to_bibtex(options = {})
      #   format = :bibtex
      #   adapter = Lutaml::Model::FormatRegistry.adapter_for(format)

      #   representation = self.class.as(format, self, options)

      #   options[:parse_encoding] = encoding if encoding
      #   adapter.new(representation).public_send(:"to_#{format}", options)
      # end

      # Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
      #   define_method(:"to_#{format}") do |options = {}|
      #     adapter = Lutaml::Model::FormatRegistry.adapter_for(format)
      #     raise Lutaml::Model::NoRootMappingError.new(self.class) if format == :xml && !self.class.root?

      #     options[:parse_encoding] = encoding if encoding
      #     self.class.to(format, self, options)
      #   end
      # end

      private

      def set_ordering(attrs)
        return unless attrs.respond_to?(:ordered?)

        @ordered = attrs.ordered?
        @element_order = attrs.item_order
      end

      def set_schema_location(attrs)
        return unless attrs.key?(:schema_location)

        self.schema_location = attrs[:schema_location]
      end

      def initialize_attributes(attrs)
        self.class.attributes.each do |name, attr|
          next if attr.derived?

          value = determine_value(attrs, name, attr)

          default = using_default?(name)
          public_send(:"#{name}=", self.class.ensure_utf8(value))
          using_default_for(name) if default
        end
      end

      def determine_value(attrs, name, attr)
        if attrs.key?(name) || attrs.key?(name.to_s)
          attr_value(attrs, name, attr)
        else
          using_default_for(name)
          attr.default
        end
      end
    end
  end
end
