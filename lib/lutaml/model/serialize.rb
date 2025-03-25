require_relative "yaml_adapter"
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
              instance_variable_set(:"@#{name}", attr.cast_value(value))
            end
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
          define_attribute_methods(attr)

          attr
        end

        def root?
          mappings_for(:xml)&.root?
        end

        def import_model_with_root_error(model)
          return unless model.mappings.key?(:xml) && model.root?

          raise Lutaml::Model::ImportModelWithRootError.new(model)
        end

        def import_model_attributes(model)
          model.attributes.each_value do |attr|
            define_attribute_methods(attr)
          end

          @choice_attributes.concat(Utils.deep_dup(model.choice_attributes))
          @attributes.merge!(Utils.deep_dup(model.attributes))
        end

        def import_model_mappings(model)
          import_model_with_root_error(model)

          Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
            next unless model.mappings.key?(format)

            mapping = model.mappings_for(format)
            mapping = Utils.deep_dup(mapping)

            @mappings[format] ||= format == :xml ? XmlMapping.new : KeyValueMapping.new

            if format == :xml
              @mappings[format].merge_mapping_attributes(mapping)
              @mappings[format].merge_mapping_elements(mapping)
              @mappings[format].merge_elements_sequence(mapping)
            else
              @mappings[format].mappings.concat(mapping.mappings)
            end
          end
        end

        def handle_key_value_mappings(mapping, format)
          @mappings[format] ||= KeyValueMapping.new
          @mappings[format].mappings.concat(mapping.mappings)
        end

        def import_model(model)
          import_model_with_root_error(model)
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

        Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
          # ruby has already a method named hash so we are using hsh
          format_name = format == :hash ? :hsh : format
          define_method(format_name) do |&block|
            process_mapping(format, &block)
          end

          define_method(:"from_#{format}") do |data, options = {}|
            from(format, data, options)
          end

          define_method(:"of_#{format}") do |doc, options = {}|
            of(format, doc, options)
          end

          define_method(:"to_#{format}") do |instance|
            to(format, instance)
          end

          define_method(:"as_#{format}") do |instance, options = {}|
            as(format, instance, options)
          end
        end

        def process_mapping(format, &block)
          klass = Lutaml::Model.const_get("#{format.to_s.capitalize}Mapping")
          mappings[format] ||= klass.new
          mappings[format].instance_eval(&block)

          handle_root_assignment(mappings, format)
        end

        def handle_root_assignment(mappings, format)
          return unless format == :xml

          if !mappings[format].root_element && !mappings[format].no_root?
            mappings[format].root(model.to_s)
          end
        end

        def from(format, data, options = {})
          return data if Utils.uninitialized?(data)

          adapter = Lutaml::Model::Config.send(:"#{format}_adapter")

          doc = adapter.parse(data, options)
          public_send(:"of_#{format}", doc, options)
        end

        def of(format, doc, options = {})
          if doc.is_a?(Array)
            return doc.map { |item| send(:"of_#{format}", item) }
          end

          if format == :xml
            raise Lutaml::Model::NoRootMappingError.new(self) unless root?

            options[:encoding] = doc.encoding
            apply_mappings(doc, format, options)
          else
            apply_mappings(doc.to_h, format, options)
          end
        end

        def to(format, instance)
          value = public_send(:"as_#{format}", instance)
          adapter = Lutaml::Model::Config.public_send(:"#{format}_adapter")

          if format == :xml
            xml_options = { mapper_class: self }
            adapter.new(value).public_send(:"to_#{format}", xml_options)
          else
            adapter.new(value).public_send(:"to_#{format}")
          end
        end

        def as(format, instance, options = {})
          if instance.is_a?(Array)
            return instance.map { |item| public_send(:"as_#{format}", item) }
          end

          unless instance.is_a?(model)
            msg = "argument is a '#{instance.class}' but should be a '#{model}'"
            raise Lutaml::Model::IncorrectModelError, msg
          end

          return instance if format == :xml

          hash_representation(instance, format, options)
        end

        def key_value(&block)
          Lutaml::Model::Config::KEY_VALUE_FORMATS.each do |format|
            mappings[format] ||= KeyValueMapping.new(format)
            mappings[format].instance_eval(&block)
          end
        end

        def hash_representation(instance, format, options = {})
          only = options[:only]
          except = options[:except]
          mappings = mappings_for(format).mappings

          mappings.each_with_object({}) do |rule, hash|
            name = rule.to
            attr = attributes[name]

            next if except&.include?(name) || (only && !only.include?(name))
            next handle_delegate(instance, rule, hash, format) if rule.delegate

            if rule.custom_methods[:to]
              next instance.send(rule.custom_methods[:to], instance, hash)
            end

            value = rule.serialize(instance)

            if rule.raw_mapping?
              adapter = Lutaml::Model::Config.send(:"#{format}_adapter")
              return adapter.parse(value, options)
            end

            value = ExportTransformer.call(value, rule, attr)

            next hash.merge!(generate_hash_from_child_mappings(attr, value, format, rule.root_mappings)) if rule.root_mapping?

            value = if rule.child_mappings
                      generate_hash_from_child_mappings(attr, value, format, rule.child_mappings)
                    else
                      attr.serialize(value, format, options)
                    end

            next if !rule.render?(value, instance, options)

            value = apply_value_map(value, rule.value_map(:to, options), attr)

            rule_from_name = rule.multiple_mappings? ? rule.from.first.to_s : rule.from.to_s
            hash[rule_from_name] = value
          end
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
          return [] if attr.collection?

          ""
        end

        def handle_delegate(instance, rule, hash, format)
          name = rule.to
          value = instance.send(rule.delegate).send(name)
          return if value.nil? && !rule.render_nil

          attribute = instance.send(rule.delegate).class.attributes[name]
          rule_from_name = rule.multiple_mappings? ? rule.from.first.to_s : rule.from.to_s
          hash[rule_from_name] = attribute.serialize(value, format)
        end

        def mappings_for(format)
          mappings[format] || default_mappings(format)
        end

        def default_mappings(format)
          _mappings = format == :xml ? XmlMapping.new : KeyValueMapping.new(format)

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

        def translate_mappings(hash, child_mappings, attr, format)
          return hash unless child_mappings

          hash.map do |key, value|
            child_hash = child_mappings.to_h do |attr_name, path|
              attr_value = if path == :key
                             key
                           elsif path == :value
                             value
                           else
                             path = [path] unless path.is_a?(Array)
                             value.dig(*path.map(&:to_s))
                           end

              attr_rule = attr.type.mappings_for(format).find_by_to(attr_name)
              [attr_rule.from.to_s, attr_value]
            end

            if child_mappings.values == [:key] && hash.values.all?(Hash)
              child_hash.merge!(value)
            end

            attr.type.apply_hash_mapping(
              child_hash,
              attr.type.model.new,
              format,
              { mappings: attr.type.mappings_for(format).mappings },
            )
          end
        end

        def generate_hash_from_child_mappings(attr, value, format, child_mappings)
          return value unless child_mappings

          hash = {}

          if child_mappings.values == [:key]
            klass = value.first.class
            mappings = klass.mappings_for(format)

            klass.attributes.each_key do |name|
              next if child_mappings.key?(name.to_sym) || child_mappings.key?(name.to_s)

              child_mappings[name.to_sym] = mappings.find_by_to(name)&.name.to_s || name.to_s
            end
          end

          value.each do |child_obj|
            map_key = nil
            map_value = {}
            mapping_rules = attr.type.mappings_for(format)

            child_mappings.each do |attr_name, path|
              mapping_rule = mapping_rules.find_by_to(attr_name)

              attr_value = child_obj.send(attr_name)

              attr_value = if attr_value.is_a?(Lutaml::Model::Serialize)
                             attr_value.to_yaml_hash
                           elsif attr_value.is_a?(Array) && attr_value.first.is_a?(Lutaml::Model::Serialize)
                             attr_value.map(&:to_yaml_hash)
                           else
                             attr_value
                           end

              next unless mapping_rule&.render?(attr_value, nil)

              if path == :key
                map_key = attr_value
              elsif path == :value
                map_value = attr_value
              else
                path = [path] unless path.is_a?(Array)
                path[0...-1].inject(map_value) do |acc, k|
                  acc[k.to_s] ||= {}
                end.public_send(:[]=, path.last.to_s, attr_value)
              end
            end

            map_value = nil if map_value.empty?
            hash[map_key] = map_value
          end

          hash
        end

        def valid_rule?(rule)
          attribute = attribute_for_rule(rule)

          !!attribute || rule.custom_methods[:from]
        end

        def attribute_for_rule(rule)
          return attributes[rule.to] unless rule.delegate

          attributes[rule.delegate].type.attributes[rule.to]
        end

        def attribute_for_child(child_name, format)
          mapping_rule = mappings_for(format).find_by_name(child_name)

          attribute_for_rule(mapping_rule) if mapping_rule
        end

        def apply_mappings(doc, format, options = {})
          instance = options[:instance] || model.new
          return instance if Utils.blank?(doc)

          mappings = mappings_for(format)

          if mappings.polymorphic_mapping
            return resolve_polymorphic(doc, format, mappings, instance, options)
          end

          options[:mappings] = mappings.mappings
          return apply_xml_mapping(doc, instance, options) if format == :xml

          apply_hash_mapping(doc, instance, format, options)
        end

        def resolve_polymorphic(doc, format, mappings, instance, options = {})
          polymorphic_mapping = mappings.polymorphic_mapping
          return instance if polymorphic_mapping.polymorphic_map.empty?

          klass_key = doc[polymorphic_mapping.name]
          klass_name = polymorphic_mapping.polymorphic_map[klass_key]
          klass = Object.const_get(klass_name)

          klass.apply_mappings(doc, format, options)
        end

        def apply_xml_mapping(doc, instance, options = {})
          options = prepare_options(options)
          instance.encoding = options[:encoding]
          return instance unless doc

          mappings = options[:mappings] || mappings_for(:xml).mappings

          validate_document!(doc, options)

          set_instance_ordering(instance, doc, options)
          set_schema_location(instance, doc)

          defaults_used = []
          validate_sequence!(doc.root.order)

          mappings.each do |rule|
            raise "Attribute '#{rule.to}' not found in #{self}" unless valid_rule?(rule)

            attr = attribute_for_rule(rule)
            next if attr&.derived?

            new_opts = options.dup
            if rule.namespace_set?
              new_opts[:default_namespace] = rule.namespace
            end

            value = if rule.raw_mapping?
                      doc.root.inner_xml
                    elsif rule.content_mapping?
                      rule.cdata ? doc.cdata : doc.text
                    else
                      val = value_for_rule(doc, rule, new_opts, instance)

                      if (Utils.uninitialized?(val) || val.nil?) && (instance.using_default?(rule.to) || rule.render_default)
                        defaults_used << rule.to
                        attr&.default || rule.to_value_for(instance)
                      else
                        val
                      end
                    end

            value = apply_value_map(value, rule.value_map(:from, new_opts), attr)
            value = normalize_xml_value(value, rule, attr, new_opts)
            rule.deserialize(instance, value, attributes, self)
          end

          defaults_used.each do |attr_name|
            instance.using_default_for(attr_name)
          end

          instance
        end

        def prepare_options(options)
          opts = Utils.deep_dup(options)
          opts[:default_namespace] ||= mappings_for(:xml)&.namespace_uri

          opts
        end

        def validate_document!(doc, options)
          return unless doc.is_a?(Array)

          raise Lutaml::Model::CollectionTrueMissingError(
            self,
            options[:caller_class],
          )
        end

        def set_instance_ordering(instance, doc, options)
          return unless instance.respond_to?(:ordered=)

          instance.element_order = doc.root.order
          instance.ordered = mappings_for(:xml).ordered? || options[:ordered]
          instance.mixed = mappings_for(:xml).mixed_content? || options[:mixed_content]
        end

        def set_schema_location(instance, doc)
          schema_location = doc.attributes.values.find do |a|
            a.unprefixed_name == "schemaLocation"
          end

          return if schema_location.nil?

          instance.schema_location = Lutaml::Model::SchemaLocation.new(
            schema_location: schema_location.value,
            prefix: schema_location.namespace_prefix,
            namespace: schema_location.namespace,
          )
        end

        def value_for_rule(doc, rule, options, instance)
          rule_names = rule.namespaced_names(options[:default_namespace])

          if rule.attribute?
            doc.root.find_attribute_value(rule_names)
          else
            attr = attribute_for_rule(rule)
            children = doc.children.select do |child|
              rule_names.include?(child.namespaced_name) && !child.text?
            end

            if rule.using_custom_methods? || attr.type == Lutaml::Model::Type::Hash
              return_child = attr.type == Lutaml::Model::Type::Hash || !attr.collection? if attr
              return return_child ? children.first : children
            end

            return handle_cdata(children) if rule.cdata

            values = []

            if Utils.present?(children)
              instance.value_set_for(attr.name)
            else
              children = nil
              values = Lutaml::Model::UninitializedClass.instance
            end

            children&.each do |child|
              if !rule.using_custom_methods? && attr.type <= Serialize
                cast_options = options.except(:mappings)
                cast_options[:polymorphic] = rule.polymorphic if rule.polymorphic

                values << attr.cast(child, :xml, cast_options)
              elsif attr.raw?
                values << inner_xml_of(child)
              else
                return nil if rule.render_nil_as_nil? && child.nil_element?

                text = child.nil_element? ? nil : (child&.text&.+ child&.cdata)
                values << text
              end
            end

            normalized_value_for_attr(values, attr)
          end
        end

        def handle_cdata(children)
          values = children.map do |child|
            child.cdata_children&.map(&:text)
          end.flatten

          children.count > 1 ? values : values.first
        end

        def normalized_value_for_attr(values, attr)
          # for xml collection true cases like
          #   <store><items /></store>
          #   <store><items xsi:nil="true"/></store>
          #   <store><items></items></store>
          #
          # these are considered empty collection
          return [] if attr&.collection? && [[nil], [""]].include?(values)
          return values if attr&.collection?

          values.is_a?(Array) ? values.first : values
        end

        def apply_hash_mapping(doc, instance, format, options = {})
          mappings = options[:mappings] || mappings_for(format).mappings
          mappings.each do |rule|
            raise "Attribute '#{rule.to}' not found in #{self}" unless valid_rule?(rule)

            attr = attribute_for_rule(rule)
            next if attr&.derived?

            names = rule.multiple_mappings? ? rule.name : [rule.name]

            values = names.collect do |rule_name|
              if rule.root_mapping?
                doc
              elsif rule.raw_mapping?
                adapter = Lutaml::Model::Config.public_send(:"#{format}_adapter")
                adapter.new(doc).public_send(:"to_#{format}")
              elsif doc.key?(rule_name.to_s)
                doc[rule_name.to_s]
              elsif doc.key?(rule_name.to_sym)
                doc[rule_name.to_sym]
              elsif attr&.default_set?
                attr&.default
              else
                Lutaml::Model::UninitializedClass.instance
              end
            end.compact

            value = values.find { |v| Utils.initialized?(v) } || values.first

            value = apply_value_map(value, rule.value_map(:from, options), attr)

            if rule.using_custom_methods?
              if Utils.present?(value)
                value = new.send(rule.custom_methods[:from], instance, value)
              end

              next
            end

            value = translate_mappings(value, rule.hash_mappings, attr, format)

            cast_options = {}
            cast_options[:polymorphic] = rule.polymorphic if rule.polymorphic

            value = attr.cast(value, format, cast_options) unless rule.hash_mappings
            attr.valid_collection!(value, self)

            rule.deserialize(instance, value, attributes, self)
          end

          instance
        end

        def normalize_xml_value(value, rule, attr, options = {})
          value = [value].compact if attr&.collection? && !value.is_a?(Array) && !value.nil?

          return value unless cast_value?(attr, rule)

          options.merge(caller_class: self, mixed_content: rule.mixed_content)
          attr.cast(
            value,
            :xml,
            options,
          )
        end

        def cast_value?(attr, rule)
          attr &&
            !rule.raw_mapping? &&
            !rule.content_mapping? &&
            !rule.custom_methods[:from]
        end

        def text_hash?(attr, value)
          return false unless value.is_a?(Hash)
          return value.one? && value.text? unless attr

          !(attr.type <= Serialize) && attr.type != Lutaml::Model::Type::Hash
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

        def validate_sequence!(element_order)
          mapping_sequence = mappings_for(:xml).element_sequence
          current_order = element_order.filter_map(&:element_tag)

          mapping_sequence.each do |mapping|
            mapping.validate_content!(current_order)
          end
        end

        private

        def inner_xml_of(node)
          case node
          when XmlAdapter::XmlElement
            node.inner_xml
          else
            node.children.map(&:to_xml).join
          end
        end
      end

      attr_accessor :element_order, :schema_location, :encoding
      attr_writer :ordered, :mixed

      def initialize(attrs = {}, options = {})
        @using_default = {}

        return unless self.class.attributes

        if attrs.is_a?(Lutaml::Model::MappingHash)
          @ordered = attrs.ordered?
          @element_order = attrs.item_order
        end

        if attrs.key?(:schema_location)
          self.schema_location = attrs[:schema_location]
        end

        self.class.attributes.each do |name, attr|
          next if attr.derived?

          value = if attrs.key?(name) || attrs.key?(name.to_s)
                    attr_value(attrs, name, attr)
                  elsif attr.default_set?
                    using_default_for(name)
                    attr.default
                  else
                    Lutaml::Model::UninitializedClass.instance
                  end

          default = using_default?(name)
          value = self.class.apply_value_map(value, value_map(options), attr)
          public_send(:"#{name}=", self.class.ensure_utf8(value))
          using_default_for(name) if default
        end
      end

      def value_map(options)
        {
          omitted: options[:omitted] || :nil,
          nil: options[:nil] || :nil,
          empty: options[:empty] || :empty,
        }
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

      def attribute_exist?(attr_name)
        attr_name = attr_name.to_s.chomp("=").to_sym if attr_name.end_with?("=")
        self.class.attributes.key?(attr_name)
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

      Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
        define_method(:"to_#{format}") do |options = {}|
          adapter = Lutaml::Model::Config.public_send(:"#{format}_adapter")
          raise NoRootMappingError.new(self.class) unless self.class.root?

          representation = if format == :xml
                             self
                           else
                             self.class.hash_representation(self, format,
                                                            options)
                           end

          options[:parse_encoding] = encoding if encoding
          adapter.new(representation).public_send(:"to_#{format}", options)
        end
      end
    end
  end
end
