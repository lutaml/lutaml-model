require_relative "yaml_adapter"
require_relative "xml_adapter"
require_relative "config"
require_relative "type"
require_relative "attribute"
require_relative "mapping_rule"
require_relative "mapping_hash"
require_relative "xml_mapping"
require_relative "key_value_mapping"
require_relative "json_adapter"

module Lutaml
  module Model
    module Serialize
      FORMATS = %i[xml json yaml toml].freeze

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        attr_accessor :attributes, :mappings

        def inherited(subclass)
          super

          @mappings ||= {}
          @attributes ||= {}

          subclass.instance_variable_set(:@attributes, @attributes.dup)
          subclass.instance_variable_set(:@mappings, @mappings.dup)
          subclass.instance_variable_set(:@model, subclass)
        end

        def model(klass = nil)
          if klass
            @model = klass
          else
            @model
          end
        end

        # Define an attribute for the model
        def attribute(name, type, options = {})
          attr = Attribute.new(name, type, options)
          attributes[name] = attr

          define_method(name) do
            instance_variable_get(:"@#{name}")
          end

          define_method(:"#{name}=") do |value|
            unless self.class.attr_value_valid?(name, value)
              raise Lutaml::Model::InvalidValueError.new(name, value, options[:values])
            end

            instance_variable_set(:"@#{name}", value)
          end
        end

        # Check if the value to be assigned is valid for the attribute
        def attr_value_valid?(name, value)
          attr = attributes[name]

          return true unless attr.options[:values]

          # If value validation failed but there is a default value, do not
          # raise a validation error
          attr.options[:values].include?(value || attr.default)
        end

        FORMATS.each do |format|
          define_method(format) do |&block|
            klass = format == :xml ? XmlMapping : KeyValueMapping
            mappings[format] = klass.new
            mappings[format].instance_eval(&block)

            if format == :xml && !mappings[format].root_element
              mappings[format].root(model.to_s)
            end
          end

          define_method(:"from_#{format}") do |data|
            adapter = Lutaml::Model::Config.send(:"#{format}_adapter")
            doc = adapter.parse(data)
            mapped_attrs = apply_mappings(doc.to_h, format)
            # apply_content_mapping(doc, mapped_attrs) if format == :xml
            generate_model_object(self, mapped_attrs)
          end

          define_method(:"to_#{format}") do |instance|
            unless instance.is_a?(model)
              msg = "argument is a '#{instance.class}' but should be a '#{model}'"
              raise Lutaml::Model::IncorrectModelError, msg
            end

            adapter = Lutaml::Model::Config.public_send(:"#{format}_adapter")

            if format == :xml
              xml_options = { mapper_class: self }

              adapter.new(instance).public_send(:"to_#{format}", xml_options)
            else
              hash = hash_representation(instance, format)
              adapter.new(hash).public_send(:"to_#{format}")
            end
          end
        end

        def hash_representation(instance, format, options = {})
          only = options[:only]
          except = options[:except]
          mappings = mappings_for(format).mappings

          mappings.each_with_object({}) do |rule, hash|
            name = rule.to
            next if except&.include?(name) || (only && !only.include?(name))

            next handle_delegate(instance, rule, hash) if rule.delegate

            value = if rule.custom_methods[:to]
                      instance.send(rule.custom_methods[:to], instance, instance.send(name))
                    else
                      instance.send(name)
                    end

            next if value.nil? && !rule.render_nil

            attribute = attributes[name]

            hash[rule.from] = if rule.child_mappings
                                generate_hash_from_child_mappings(value, rule.child_mappings)
                              elsif value.is_a?(Array)
                                value.map do |v|
                                  if attribute.type <= Serialize
                                    attribute.type.hash_representation(v, format, options)
                                  else
                                    attribute.type.serialize(v)
                                  end
                                end
                              elsif attribute.type <= Serialize
                                attribute.type.hash_representation(value, format, options)
                              else
                                attribute.type.serialize(value)
                              end
          end
        end

        def handle_delegate(instance, rule, hash)
          name = rule.to
          value = instance.send(rule.delegate).send(name)
          return if value.nil? && !rule.render_nil

          attribute = instance.send(rule.delegate).class.attributes[name]
          hash[rule.from] = case value
                            when Array
                              value.map do |v|
                                if v.is_a?(Serialize)
                                  hash_representation(v, format, options)
                                else
                                  attribute.type.serialize(v)
                                end
                              end
                            else
                              if value.is_a?(Serialize)
                                hash_representation(value, format, options)
                              else
                                attribute.type.serialize(value)
                              end
                            end
        end

        def mappings_for(format)
          mappings[format] || default_mappings(format)
        end

        def generate_model_object(type, mapped_attrs)
          return type.model.new(mapped_attrs) if self == model

          instance = type.model.new

          type.attributes.each do |name, attr|
            value = attr_value(mapped_attrs, name, attr)

            instance.send(:"#{name}=", ensure_utf8(value))
          end

          instance
        end

        def attr_value(attrs, name, attr_rule)
          value = if attrs.key?(name)
                    attrs[name]
                  elsif attrs.key?(name.to_sym)
                    attrs[name.to_sym]
                  elsif attrs.key?(name.to_s)
                    attrs[name.to_s]
                  else
                    attr_rule.default
                  end

          if attr_rule.collection? || value.is_a?(Array)
            (value || []).map do |v|
              if v.is_a?(Hash)
                attr_rule.type.new(v)
              else
                # TODO: This code is problematic because Type.cast does not know
                # about all the types.
                Lutaml::Model::Type.cast(
                  v, attr_rule.type
                )
              end
            end
          elsif value.is_a?(Hash) && attr_rule.type != Lutaml::Model::Type::Hash
            generate_model_object(attr_rule.type, value)
          else
            # TODO: This code is problematic because Type.cast does not know
            # about all the types.
            Lutaml::Model::Type.cast(value, attr_rule.type)
          end
        end

        def default_mappings(format)
          klass = format == :xml ? XmlMapping : KeyValueMapping
          klass.new.tap do |mapping|
            attributes&.each do |name, attr|
              mapping.map_element(
                name.to_s,
                to: name,
                render_nil: attr.render_nil?,
              )
            end
          end
        end

        def apply_child_mappings(hash, child_mappings)
          return hash unless child_mappings

          hash.map do |key, value|
            child_mappings.to_h do |attr_name, path|
              attr_value = if path == :key
                             key
                           elsif path == :value
                             value
                           else
                             path = [path] unless path.is_a?(Array)
                             value.dig(*path.map(&:to_s))
                           end

              [attr_name, attr_value]
            end
          end
        end

        def generate_hash_from_child_mappings(value, child_mappings)
          return value unless child_mappings

          hash = {}

          value.each do |child_obj|
            map_key = nil
            map_value = {}
            child_mappings.each do |attr_name, path|
              if path == :key
                map_key = child_obj.send(attr_name)
              elsif path == :value
                map_value = child_obj.send(attr_name)
              else
                path = [path] unless path.is_a?(Array)
                path[0...-1].inject(map_value) do |acc, k|
                  acc[k.to_s] ||= {}
                end.public_send(:[]=, path.last.to_s, child_obj.send(attr_name))
              end
            end
            # hash[mapping.name] ||= {}
            hash[map_key] = map_value
          end

          hash
        end

        def apply_mappings(doc, format)
          return apply_xml_mapping(doc) if format == :xml

          mappings = mappings_for(format).mappings
          mappings.each_with_object(Lutaml::Model::MappingHash.new) do |rule, hash|
            attr = if rule.delegate
                     attributes[rule.delegate].type.attributes[rule.to]
                   else
                     attributes[rule.to]
                   end

            raise "Attribute '#{rule.to}' not found in #{self}" unless attr

            value = if rule.custom_methods[:from]
                      new.send(rule.custom_methods[:from], hash, doc)
                    elsif doc.key?(rule.name) || doc.key?(rule.name.to_sym)
                      doc[rule.name] || doc[rule.name.to_sym]
                    else
                      attr.default
                    end

            value = apply_child_mappings(value, rule.child_mappings)

            if attr.collection?
              value = (value || []).map do |v|
                attr.type <= Serialize ? attr.type.apply_mappings(v, format) : v
              end
            elsif value.is_a?(Hash) && attr.type != Lutaml::Model::Type::Hash
              value = attr.type.apply_mappings(value, format)
            end

            if rule.delegate
              hash[rule.delegate] ||= {}
              hash[rule.delegate][rule.to] = value
            else
              hash[rule.to] = value
            end
          end
        end

        def apply_xml_mapping(doc, caller_class: nil, mixed_content: false)
          return unless doc

          mappings = mappings_for(:xml).mappings

          if doc.is_a?(Array)
            raise "May be `collection: true` is" \
                  "missing for #{self} in #{caller_class}"
          end

          mapping_hash = Lutaml::Model::MappingHash.new
          mapping_hash.item_order = doc.item_order
          mapping_hash.ordered = mappings_for(:xml).mixed_content? || mixed_content

          mappings.each_with_object(mapping_hash) do |rule, hash|
            attr = attributes[rule.to]
            raise "Attribute '#{rule.to}' not found in #{self}" unless attr

            is_content_mapping = rule.name.nil?
            value = if is_content_mapping
                      doc["text"]
                    else
                      doc[rule.name.to_s] || doc[rule.name.to_sym]
                    end

            if attr.collection?
              if value && !value.is_a?(Array)
                value = [value]
              end

              value = (value || []).map do |v|
                if attr.type <= Serialize
                  attr.type.apply_xml_mapping(v, caller_class: self, mixed_content: rule.mixed_content)
                elsif v.is_a?(Hash)
                  v["text"]
                else
                  v
                end
              end
            elsif attr.type <= Serialize
              value = attr.type.apply_xml_mapping(value, caller_class: self, mixed_content: rule.mixed_content)
            else
              if value.is_a?(Hash) && attr.type != Lutaml::Model::Type::Hash
                value = value["text"]
              end

              value = attr.type.cast(value) unless is_content_mapping
            end

            hash[rule.to] = value
          end
        end

        def ensure_utf8(value)
          case value
          when String
            value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          when Array
            value.map { |v| ensure_utf8(v) }
          when Hash
            value.transform_keys do |k|
              ensure_utf8(k)
            end.transform_values { |v| ensure_utf8(v) }
          else
            value
          end
        end
      end

      attr_reader :element_order

      def initialize(attrs = {})
        return unless self.class.attributes

        if attrs.is_a?(Lutaml::Model::MappingHash)
          @ordered = attrs.ordered?
          @element_order = attrs.item_order
        end

        self.class.attributes.each do |name, attr|
          value = self.class.attr_value(attrs, name, attr)

          send(:"#{name}=", self.class.ensure_utf8(value))
        end
      end

      def ordered?
        @ordered
      end

      def key_exist?(hash, key)
        hash.key?(key) || hash.key?(key.to_sym) || hash.key?(key.to_s)
      end

      def key_value(hash, key)
        hash[key] || hash[key.to_sym] || hash[key.to_s]
      end

      FORMATS.each do |format|
        define_method(:"to_#{format}") do |options = {}|
          adapter = Lutaml::Model::Config.public_send(:"#{format}_adapter")
          representation = if format == :xml
                             self
                           else
                             self.class.hash_representation(self, format, options)
                           end

          adapter.new(representation).public_send(:"to_#{format}", options)
        end
      end
    end
  end
end
