require_relative "xml_adapter"
require_relative "config"
require_relative "type"
require_relative "attribute"
require_relative "mapping_hash"
require_relative "json_adapter"
require_relative "comparable_model"
require_relative "schema_location"
require_relative "validation"
require_relative "error"
require_relative "choice"
require_relative "sequence"
require_relative "liquefiable"
require_relative "transform"
require_relative "registrable"

module Lutaml
  module Model
    module Serialize
      include ComparableModel
      include Validation
      include Lutaml::Model::Liquefiable
      include Lutaml::Model::Registrable

      def self.included(base)
        base.extend(ClassMethods)
        base.initialize_attrs(base)
      end

      module ClassMethods
        include Lutaml::Model::Liquefiable::ClassMethods

        INTERNAL_ATTRIBUTES = %i[@using_default @__register].freeze

        attr_accessor :choice_attributes, :mappings

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

        def attributes(register = nil)
          ensure_imports!(register) if finalized?
          @attributes
        end

        def ensure_imports!(register = nil)
          ensure_model_imports!(register)
          ensure_choice_imports!(register)
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

        def define_attribute_methods(attr)
          name = attr.name

          if attr.enum?
            add_enum_methods_to_model(
              model,
              name,
              attr.options[:values],
              collection: attr.options[:collection],
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
              instance_variable_set(:"@#{name}", attr.cast_value(value, __register))
            end
          end
        end

        # Define an attribute for the model
        def attribute(name, type, options = {})
          if type.is_a?(::Hash)
            options[:method_name] = type[:method]
            type = nil
          end

          attr = Attribute.new(name, type, options)
          attributes[name] = attr
          define_attribute_methods(attr)

          attr
        end

        def restrict(name, options = {})
          validate_attribute_options!(name, options)
          attr = attributes[name]
          attr.options.merge!(options)
          attr.process_options!
          name
        end

        def validate_attribute_options!(name, options)
          invalid_opts = options.keys - Attribute::ALLOWED_OPTIONS
          return if invalid_opts.empty?

          raise Lutaml::Model::InvalidAttributeOptionsError.new(name, invalid_opts)
        end

        def register(name)
          name&.to_sym
        end

        def root?
          mappings_for(:xml)&.root?
        end

        def import_model_with_root_error(model)
          return unless model.mappings.key?(:xml) && model.root?

          raise Lutaml::Model::ImportModelWithRootError.new(model)
        end

        def import_model_attributes(model)
          if model.is_a?(Symbol) || model.is_a?(String)
            importable_models[:import_model_attributes] << model.to_sym
            @models_imported = false
            @choices_imported = false
            setup_trace_point
            return
          end

          model.attributes.each_value do |attr|
            define_attribute_methods(attr)
          end

          @choice_attributes.concat(Utils.deep_dup(model.choice_attributes))
          @attributes.merge!(Utils.deep_dup(model.attributes))
        end

        def import_model_mappings(model)
          if model.is_a?(Symbol) || model.is_a?(String)
            importable_models[:import_model_mappings] << model.to_sym
            @models_imported = false
            setup_trace_point
            return
          end

          import_model_with_root_error(model)
          Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
            next unless model.mappings.key?(format)

            mapping = model.mappings_for(format)
            mapping = Utils.deep_dup(mapping)

            klass = ::Lutaml::Model::Config.mappings_class_for(format)
            @mappings[format] ||= klass.new

            if format == :xml
              @mappings[format].merge_mapping_attributes(mapping)
              @mappings[format].merge_mapping_elements(mapping)
              @mappings[format].merge_elements_sequence(mapping)
            else
              @mappings[format].mappings_hash.merge!(mapping.mappings_hash)
            end
          end
        end

        def handle_key_value_mappings(mapping, format)
          @mappings[format] ||= KeyValueMapping.new
          @mappings[format].mappings_hash.merge!(mapping.mappings_hash)
        end

        def import_model(model)
          if model.is_a?(Symbol) || model.is_a?(String)
            importable_models[:import_model] << model.to_sym
            @models_imported = false
            @choices_imported = false
            setup_trace_point
            return
          end

          import_model_with_root_error(model)
          import_model_attributes(model)
          import_model_mappings(model)
        end

        def importable_models
          @importable_models ||= MappingHash.new { |h, k| h[k] = [] }
        end

        def importable_choices
          @importable_choices ||= MappingHash.new { |h, k| h[k] = MappingHash.new { |h1, k1| h1[k1] = [] } }
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

        def process_mapping(format, &block)
          klass = ::Lutaml::Model::Config.mappings_class_for(format)
          mappings[format] ||= klass.new
          mappings[format].instance_eval(&block)

          if mappings[format].respond_to?(:finalize)
            mappings[format].finalize(self)
          end

          check_sort_configs! if format == :xml
        end

        def from(format, data, options = {})
          adapter = Lutaml::Model::Config.adapter_for(format)

          doc = adapter.parse(data, options)
          send("of_#{format}", doc, options)
        rescue *format_error_types => e
          raise Lutaml::Model::InvalidFormatError.new(format, e.message)
        end

        def format_error_types
          errors = [
            Psych::SyntaxError,
            JSON::ParserError,
            NoMethodError,
            TypeError,
            ArgumentError,
          ]

          %w[
            Nokogiri::XML::SyntaxError
            Ox::ParseError
            TomlRB::ParseError
            Tomlib::ParseError
          ].each do |error_class|
            errors << safe_get_const(error_class)
          end

          errors.compact
        end

        def safe_get_const(error_class)
          return unless Object.const_defined?(error_class.split("::").first)

          error_class.split("::").inject(Object) { |mod, part| mod.const_get(part) }
        end

        def of(format, doc, options = {})
          if doc.is_a?(Array) && format != :jsonl
            return doc.map { |item| send(:"of_#{format}", item) }
          end

          if format == :xml
            valid = root? || options[:from_collection]
            raise Lutaml::Model::NoRootMappingError.new(self) unless valid

            options[:encoding] = doc.encoding
          end
          options[:register] = extract_register_id(options[:register])

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.data_to_model(self, doc, format, options)
        end

        def to(format, instance, options = {})
          value = public_send(:"as_#{format}", instance, options)
          adapter = Lutaml::Model::Config.adapter_for(format)

          options[:mapper_class] = self if format == :xml
          adapter.new(value).public_send(:"to_#{format}", options)
        end

        def as(format, instance, options = {})
          if instance.is_a?(Array)
            return instance.map { |item| public_send(:"as_#{format}", item) }
          end

          unless instance.is_a?(model)
            msg = "argument is a '#{instance.class}' but should be a '#{model}'"
            raise Lutaml::Model::IncorrectModelError, msg
          end

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.model_to_data(self, instance, format, options)
        end

        def key_value(&block)
          Lutaml::Model::Config::KEY_VALUE_FORMATS.each do |format|
            mappings[format] ||= KeyValueMapping.new(format)
            mappings[format].instance_eval(&block)
          end
        end

        def mappings_for(format)
          @mappings[:xml]&.ensure_mappings_imported! if @mappings&.dig(:xml)&.finalized?
          mappings[format] || default_mappings(format)
        end

        def default_mappings(format)
          klass = ::Lutaml::Model::Config.mappings_class_for(format)
          mappings = klass.new

          mappings.tap do |mapping|
            attributes&.each_key do |name|
              mapping.map_element(
                name.to_s,
                to: name,
              )
            end

            mapping.root(Utils.base_class_name(self)) if format == :xml
          end
        end

        def apply_mappings(doc, format, options = {})
          register = options[:register] || Lutaml::Model::Config.default_register
          instance = if options.key?(:instance)
                       options[:instance]
                     elsif model.include?(Lutaml::Model::Serialize)
                       model.new({ __register: register })
                     else
                       object = model.new
                       register_accessor_methods_for(object, register)
                       object
                     end
          return instance if Utils.blank?(doc)

          mappings = mappings_for(format)

          if mappings.polymorphic_mapping
            return resolve_polymorphic(doc, format, mappings, instance, options)
          end

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.data_to_model(self, doc, format, options)
        end

        def resolve_polymorphic(doc, format, mappings, instance, options = {})
          polymorphic_mapping = mappings.polymorphic_mapping
          return instance if polymorphic_mapping.polymorphic_map.empty?

          klass_key = doc[polymorphic_mapping.name]
          klass_name = polymorphic_mapping.polymorphic_map[klass_key]
          klass = Object.const_get(klass_name)

          klass.apply_mappings(doc, format, options.merge(register: instance.__register))
        end

        def apply_value_map(value, value_map, attr)
          if value.nil?
            value_for_option(value_map[:nil], attr)
          elsif Utils.empty?(value)
            value_for_option(value_map[:empty], attr, value)
          elsif Utils.uninitialized?(value)
            value_for_option(value_map[:omitted], attr)
          else
            value
          end
        end

        def value_for_option(option, attr, empty_value = nil)
          return nil if option == :nil
          return empty_value || empty_object(attr) if option == :empty

          Lutaml::Model::UninitializedClass.instance
        end

        def empty_object(attr)
          return attr.build_collection if attr.collection?

          ""
        end

        def ensure_utf8(value)
          case value
          when String
            value.encode("UTF-8", invalid: :replace, undef: :replace,
                                  replace: "")
          when Array
            value.map { |v| ensure_utf8(v) }
          when ::Hash
            value.transform_keys do |k|
              ensure_utf8(k)
            end.transform_values do |v|
              ensure_utf8(v)
            end
          else
            value
          end
        end

        def register_accessor_methods_for(object, register)
          Utils.add_singleton_method_if_not_defined(object, :__register) do
            @__register
          end
          Utils.add_singleton_method_if_not_defined(object, :__register=) do |value|
            @__register = value
          end
          object.__register = register
        end

        def extract_register_id(register)
          if register
            register.is_a?(Lutaml::Model::Register) ? register.id : register
          elsif class_variable_defined?(:@@__register)
            class_variable_get(:@@__register)
          else
            Lutaml::Model::Config.default_register
          end
        end

        def ensure_model_imports!(register_id = nil)
          return if @models_imported

          register_id ||= Lutaml::Model::Config.default_register
          register = Lutaml::Model::GlobalRegister.lookup(register_id)
          importable_models.each do |method, models|
            models.uniq.each do |model|
              model_class = register.get_class_without_register(model)
              import_model_with_root_error(model_class)

              @model.public_send(method, model_class)
            end
          end

          @models_imported = true
        end

        def ensure_choice_imports!(register_id = nil)
          return if @choices_imported

          register_id ||= Lutaml::Model::Config.default_register
          register = Lutaml::Model::GlobalRegister.lookup(register_id)
          importable_choices.each do |choice, choice_imports|
            choice_imports.each do |method, models|
              models.uniq!
              choice.public_send(method, register.get_class_without_register(models.shift)) until models.empty?
            end
          end

          @choices_imported = true
        end

        def setup_trace_point
          @trace ||= TracePoint.new(:end) do |_tp|
            if include?(Lutaml::Model::Serialize)
              @finalized = true
              @trace.disable
            end
          end
          @trace.enable unless @trace.enabled?
        end

        def finalized?
          @finalized
        end

        def check_sort_configs!
          return unless collection_with_conflicting_sort?

          raise Lutaml::Model::SortingConfigurationConflictError.new
        end

        def collection_with_conflicting_sort?
          self <= Lutaml::Model::Collection &&
            @mappings[:xml].ordered &&
            !!@sort_by_field
        end
      end

      def self.register_format_mapping_method(format)
        method_name = format == :hash ? :hsh : format

        ::Lutaml::Model::Serialize::ClassMethods.define_method(method_name) do |&block|
          process_mapping(format, &block)
        end
      end

      def self.register_from_format_method(format)
        ClassMethods.define_method(:"from_#{format}") do |data, options = {}|
          from(format, data, options)
        end

        ClassMethods.define_method(:"of_#{format}") do |doc, options = {}|
          of(format, doc, options)
        end
      end

      def self.register_to_format_method(format)
        ClassMethods.define_method(:"to_#{format}") do |instance, options = {}|
          to(format, instance, options)
        end

        ClassMethods.define_method(:"as_#{format}") do |instance, options = {}|
          as(format, instance, options)
        end

        define_method(:"to_#{format}") do |options = {}|
          to_format(format, options)
        end
      end

      attr_accessor :element_order, :schema_location, :encoding, :__register
      attr_writer :ordered, :mixed

      def initialize(attrs = {}, options = {})
        @using_default = {}
        return unless self.class.attributes

        @__register = extract_register_id(attrs, options)
        set_ordering(attrs)
        set_schema_location(attrs)
        initialize_attributes(attrs, options)
      end

      def extract_register_id(attrs, options)
        register = attrs&.dig(:__register) || options&.dig(:register)
        self.class.extract_register_id(register)
      end

      def value_map(options)
        {
          omitted: options[:omitted] || :nil,
          nil: options[:nil] || :nil,
          empty: options[:empty] || :empty,
        }
      end

      def attr_value(attrs, name, attribute)
        value = Utils.fetch_str_or_sym(attrs, name, attribute.default(__register))
        attribute.cast_value(value, __register)
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
        if method_name.to_s.end_with?("=") && attribute_exist?(method_name)
          define_singleton_method(method_name) do |value|
            instance_variable_set(:"@#{method_name.to_s.chomp('=')}", value)
          end
          send(method_name, *args)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        (method_name.to_s.end_with?("=") && attribute_exist?(method_name)) ||
          super
      end

      def attribute_exist?(name)
        name = name.to_s.chomp("=").to_sym if name.end_with?("=")

        self.class.attributes.key?(name)
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
        (instance_variables - INTERNAL_ATTRIBUTES).sort
      end

      def to_yaml_hash
        self.class.as_yaml(self)
      end

      def to_format(format, options = {})
        validate_root_mapping!(format, options)

        options[:parse_encoding] = encoding if encoding
        self.class.to(format, self, options)
      end

      private

      def validate_root_mapping!(format, options)
        return if format != :xml
        return if options[:collection] || self.class.root?

        raise Lutaml::Model::NoRootMappingError.new(self.class)
      end

      def set_ordering(attrs)
        return unless attrs.respond_to?(:ordered?)

        @ordered = attrs.ordered?
        @element_order = attrs.item_order
      end

      def set_schema_location(attrs)
        return unless attrs.key?(:schema_location)

        self.schema_location = attrs[:schema_location]
      end

      def initialize_attributes(attrs, options = {})
        self.class.attributes.each do |name, attr|
          next if attr.derived?

          value = determine_value(attrs, name, attr)

          default = using_default?(name)
          value = self.class.apply_value_map(value, value_map(options), attr)
          public_send(:"#{name}=", self.class.ensure_utf8(value))
          using_default_for(name) if default
        end
      end

      def determine_value(attrs, name, attr)
        if attrs.key?(name) || attrs.key?(name.to_s)
          attr_value(attrs, name, attr)
        elsif attr.default_set?(__register)
          using_default_for(name)
          attr.default(__register)
        else
          Lutaml::Model::UninitializedClass.instance
        end
      end
    end
  end
end
