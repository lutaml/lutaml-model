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
require_relative "comparable_model"
require_relative "schema_location"

module Lutaml
  module Model
    module Serialize
      include ComparableModel

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
            instance_variable_set(:"@#{name}", value)
            validate!(name)
          end
        end

        Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
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
            public_send(:"of_#{format}", doc.to_h)
          end

          define_method(:"of_#{format}") do |hash|
            if hash.is_a?(Array)
              return hash.map do |item|
                       apply_mappings(item, format)
                     end
            end

            apply_mappings(hash, format)
          end

          define_method(:"to_#{format}") do |instance|
            value = public_send(:"as_#{format}", instance)
            adapter = Lutaml::Model::Config.public_send(:"#{format}_adapter")

            if format == :xml
              xml_options = { mapper_class: self }
              adapter.new(value).public_send(:"to_#{format}", xml_options)
            else
              adapter.new(value).public_send(:"to_#{format}")
            end
          end

          define_method(:"as_#{format}") do |instance|
            if instance.is_a?(Array)
              return instance.map { |item| public_send(:"as_#{format}", item) }
            end

            unless instance.is_a?(model)
              msg = "argument is a '#{instance.class}' but should be a '#{model}'"
              raise Lutaml::Model::IncorrectModelError, msg
            end

            return instance if format == :xml

            hash_representation(instance, format)
          end
        end

        def hash_representation(instance, format, options = {})
          only = options[:only]
          except = options[:except]
          mappings = mappings_for(format).mappings

          mappings.each_with_object({}) do |rule, hash|
            name = rule.to
            next if except&.include?(name) || (only && !only.include?(name))

            next handle_delegate(instance, rule, hash, format) if rule.delegate

            if rule.custom_methods[:to]
              next instance.send(rule.custom_methods[:to], instance, hash)
            end

            value = instance.send(name)

            next if value.nil? && !rule.render_nil

            attribute = attributes[name]

            hash[rule.from] = if rule.child_mappings
                                generate_hash_from_child_mappings(value, rule.child_mappings)
                              else
                                attribute.serialize(value, format, options)
                              end
          end
        end

        def handle_delegate(instance, rule, hash, format)
          name = rule.to
          value = instance.send(rule.delegate).send(name)
          return if value.nil? && !rule.render_nil

          attribute = instance.send(rule.delegate).class.attributes[name]
          hash[rule.from] = attribute.serialize(value, format)
        end

        def mappings_for(format)
          mappings[format] || default_mappings(format)
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
            (value || []).map do |v|
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

            hash[map_key] = map_value
          end

          hash
        end

        def apply_mappings(doc, format, options = {})
          instance = options[:instance] || model.new
          return instance if !doc || doc.empty?
          return apply_xml_mapping(doc, instance, options) if format == :xml

          mappings = mappings_for(format).mappings
          mappings.each do |rule|
            attr = if rule.delegate
                     attributes[rule.delegate].type.attributes[rule.to]
                   else
                     attributes[rule.to]
                   end

            raise "Attribute '#{rule.to}' not found in #{self}" unless attr

            value = if doc.key?(rule.name) || doc.key?(rule.name.to_sym)
                      doc[rule.name] || doc[rule.name.to_sym]
                    else
                      attr.default
                    end

            if rule.custom_methods[:from]
              if value && !value.empty?
                value = new.send(rule.custom_methods[:from], instance,
                                 value)
              end
              next
            end

            value = apply_child_mappings(value, rule.child_mappings)
            value = attr.cast(value, format)

            if rule.delegate
              if instance.public_send(rule.delegate).nil?
                instance.public_send(:"#{rule.delegate}=",
                                     attributes[rule.delegate].type.new)
              end
              instance.public_send(rule.delegate).public_send(:"#{rule.to}=",
                                                              value)
            else
              instance.public_send(:"#{rule.to}=", value)
            end
          end

          instance
        end

        def apply_xml_mapping(doc, instance, options = {})
          return instance unless doc

          mappings = mappings_for(:xml).mappings

          if doc.is_a?(Array)
            raise "May be `collection: true` is" \
                  "missing for #{self} in #{options[:caller_class]}"
          end

          if instance.respond_to?(:ordered=) && doc.is_a?(Lutaml::Model::MappingHash)
            instance.element_order = doc.item_order
            instance.ordered = mappings_for(:xml).mixed_content? || options[:mixed_content]
          end

          if doc["__schema_location"]
            instance.schema_location = Lutaml::Model::SchemaLocation.new(
              schema_location: doc["__schema_location"][:schema_location],
              prefix: doc["__schema_location"][:prefix],
              namespace: doc["__schema_location"][:namespace],
            )
          end

          mappings.each do |rule|
            attr = attributes[rule.to]
            raise "Attribute '#{rule.to}' not found in #{self}" unless attr

            is_content_mapping = rule.name.nil?

            value = if is_content_mapping
                      doc["text"]
                    else
                      doc[rule.name.to_s] || doc[rule.name.to_sym]
                    end

            value = [value].compact if attr.collection? && !value.is_a?(Array)

            if value.is_a?(Array)
              value = value.map do |v|
                v.is_a?(Hash) && !(attr.type <= Serialize) ? v["text"] : v
              end
            elsif !(attr.type <= Serialize) && value.is_a?(Hash) && attr.type != Lutaml::Model::Type::Hash
              value = value["text"]
            end

            unless is_content_mapping
              value = attr.cast(
                value,
                :xml,
                caller_class: self,
                mixed_content: rule.mixed_content,
              )
            end

            if rule.custom_methods[:from]
              new.send(rule.custom_methods[:from], instance, value)
            else
              instance.public_send(:"#{rule.to}=", value)
            end
          end

          instance
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

      attr_accessor :element_order, :schema_location

      def initialize(attrs = {})
        return unless self.class.attributes

        if attrs.is_a?(Lutaml::Model::MappingHash)
          @ordered = attrs.ordered?
          @element_order = attrs.item_order
        end

        if attrs.key?(:schema_location)
          self.schema_location = attrs[:schema_location]
        end

        self.class.attributes.each do |name, attr|
          value = if attrs.key?(name) || attrs.key?(name.to_s)
                    self.class.attr_value(attrs, name, attr)
                  else
                    attr.default
                  end

          # Initialize collections with an empty array if no value is provided
          if attr.collection? && value.nil?
            value = []
          end

          send(:"#{name}=", self.class.ensure_utf8(value))
        end

        validate!
      end

      def ordered?
        @ordered
      end

      def ordered=(ordered)
        @ordered = ordered
      end

      def key_exist?(hash, key)
        hash.key?(key.to_sym) || hash.key?(key.to_s)
      end

      def key_value(hash, key)
        hash[key.to_sym] || hash[key.to_s]
      end

      Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
        define_method(:"to_#{format}") do |options = {}|
          validate!
          adapter = Lutaml::Model::Config.public_send(:"#{format}_adapter")
          representation = if format == :xml
                             self
                           else
                             self.class.hash_representation(self, format,
                                                            options)
                           end

          adapter.new(representation).public_send(:"to_#{format}", options)
        end
      end

      def validate!(attr_name = nil)
        self.class.attributes.each do |name, attr|
          next if attr_name && attr_name != name

          value = send(name)

          # Skip validation for nil values of non-collection attributes
          next if value.nil? && !attr.collection?

          # Always validate collections
          attr.validate_value!(value)
        end
      end
    end
  end
end
