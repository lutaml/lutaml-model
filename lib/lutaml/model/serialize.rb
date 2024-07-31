# lib/lutaml/model/serialize.rb
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

          subclass.instance_variable_set(:@attributes, @attributes.dup)
        end

        def attribute(name, type, options = {})
          self.attributes ||= {}
          attr = Attribute.new(name, type, options)
          attributes[name] = attr

          define_method(name) do
            instance_variable_get(:"@#{name}")
          end

          define_method(:"#{name}=") do |value|
            instance_variable_set(:"@#{name}", value)
          end
        end

        FORMATS.each do |format|
          define_method(format) do |&block|
            self.mappings ||= {}
            klass = format == :xml ? XmlMapping : KeyValueMapping
            self.mappings[format] = klass.new
            self.mappings[format].instance_eval(&block)

            if format == :xml && !self.mappings[format].root_element
              self.mappings[format].root(to_s)
            end
          end

          define_method(:"from_#{format}") do |data|
            adapter = Lutaml::Model::Config.send(:"#{format}_adapter")
            doc = adapter.parse(data)
            mapped_attrs = apply_mappings(doc.to_h, format)
            # apply_content_mapping(doc, mapped_attrs) if format == :xml
            new(mapped_attrs)
          end
        end

        def mappings_for(format)
          self.mappings[format] || default_mappings(format)
        end

        def default_mappings(format)
          klass = format == :xml ? XmlMapping : KeyValueMapping
          klass.new.tap do |mapping|
            attributes&.each do |name, attr|
              mapping.map_element(name.to_s, to: name,
                                             render_nil: attr.render_nil?)
            end
          end
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
      end

      attr_reader :element_order

      def initialize(attrs = {})
        return unless self.class.attributes

        if attrs.is_a?(Lutaml::Model::MappingHash)
          @ordered = attrs.ordered?
          @element_order = attrs.item_order
        end

        self.class.attributes.each do |name, attr|
          value = attr_value(attrs, name, attr)

          send(:"#{name}=", ensure_utf8(value))
        end
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
              Lutaml::Model::Type.cast(
                v, attr_rule.type
              )
            end
          end
        elsif value.is_a?(Hash) && attr_rule.type != Lutaml::Model::Type::Hash
          attr_rule.type.new(value)
        else
          Lutaml::Model::Type.cast(value, attr_rule.type)
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

      # TODO: Make this work
      # FORMATS.each do |format|
      #   define_method("to_#{format}") do |options = {}|
      #     adapter = Lutaml::Model::Config.send("#{format}_adapter")
      #     representation = if format == :yaml
      #                        self
      #                      else
      #                        hash_representation(format, options)
      #                      end
      #     adapter.new(representation).send("to_#{format}", options)
      #   end
      # end

      def to_xml(options = {})
        adapter = Lutaml::Model::Config.xml_adapter
        adapter.new(self).to_xml(options)
      end

      def to_json(options = {})
        adapter = Lutaml::Model::Config.json_adapter
        adapter.new(hash_representation(:json, options)).to_json(options)
      end

      def to_yaml(options = {})
        adapter = Lutaml::Model::Config.yaml_adapter
        adapter.to_yaml(self, options)
      end

      def to_toml(options = {})
        adapter = Lutaml::Model::Config.toml_adapter
        adapter.new(hash_representation(:toml, options)).to_toml
      end

      # TODO: END Make this work

      def hash_representation(format, options = {})
        only = options[:only]
        except = options[:except]
        mappings = self.class.mappings_for(format).mappings

        mappings.each_with_object({}) do |rule, hash|
          name = rule.to
          next if except&.include?(name) || (only && !only.include?(name))

          next handle_delegate(self, rule, hash) if rule.delegate

          value = if rule.custom_methods[:to]
                    send(rule.custom_methods[:to], self, send(name))
                  else
                    send(name)
                  end

          next if value.nil? && !rule.render_nil

          attribute = self.class.attributes[name]

          hash[rule.from] = case value
                            when Array
                              value.map do |v|
                                if v.is_a?(Serialize)
                                  v.hash_representation(format, options)
                                else
                                  attribute.type.serialize(v)
                                end
                              end
                            else
                              if value.is_a?(Serialize)
                                value.hash_representation(format, options)
                              else
                                attribute.type.serialize(value)
                              end
                            end
        end
      end

      private

      def handle_delegate(_obj, rule, hash)
        name = rule.to
        value = send(rule.delegate).send(name)
        return if value.nil? && !rule.render_nil

        attribute = send(rule.delegate).class.attributes[name]
        hash[rule.from] = case value
                          when Array
                            value.map do |v|
                              if v.is_a?(Serialize)
                                v.hash_representation(format, options)
                              else
                                attribute.type.serialize(v)
                              end
                            end
                          else
                            if value.is_a?(Serialize)
                              value.hash_representation(format, options)
                            else
                              attribute.type.serialize(value)
                            end
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
  end
end
