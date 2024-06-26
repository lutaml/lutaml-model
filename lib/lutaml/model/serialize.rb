# lib/lutaml/model/serialize.rb
require_relative "json_adapter/standard"
require_relative "json_adapter/multi_json"
require_relative "yaml_adapter"
require_relative "xml_adapter"
require_relative "toml_adapter/toml_rb_adapter"
require_relative "toml_adapter/tomlib_adapter"
require_relative "config"
require_relative "type"
require_relative "attribute"
require_relative "mapping_rule"
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

        def attribute(name, type, options = {})
          self.attributes ||= {}
          attr = Attribute.new(name, type, options)
          attributes[name] = attr

          define_method(name) do
            instance_variable_get("@#{name}")
          end

          define_method("#{name}=") do |value|
            instance_variable_set("@#{name}", value)
          end
        end

        FORMATS.each do |format|
          define_method(format) do |&block|
            self.mappings ||= {}
            klass = format == :xml ? XmlMapping : KeyValueMapping
            self.mappings[format] = klass.new
            self.mappings[format].instance_eval(&block)
          end

          define_method("from_#{format}") do |data|
            adapter = Lutaml::Model::Config.send("#{format}_adapter")
            doc = adapter.parse(data)
            mapped_attrs = apply_mappings(doc.to_h, format)
            apply_content_mapping(doc, mapped_attrs) if format == :xml
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
              mapping.map_element(name.to_s, to: name, render_nil: attr.render_nil?)
            end
          end
        end

        def apply_mappings(doc, format)
          return apply_xml_mapping(doc) if format == :xml

          mappings = mappings_for(format).mappings
          mappings.each_with_object({}) do |rule, hash|
            attr = attributes[rule.to]
            raise "Attribute '#{rule.to}' not found in #{self}" unless attr

            value = doc[rule.name]
            if attr.collection?
              value = (value || []).map { |v| attr.type <= Serialize ? attr.type.new(v) : v }
            elsif value.is_a?(Hash) && attr.type <= Serialize
              value = attr.type.new(value)
            else
              value = attr.type.cast(value)
            end
            hash[rule.to] = value
          end
        end

        def apply_xml_mapping(doc)
          mappings = mappings_for(:xml).mappings

          mappings.each_with_object({}) do |rule, hash|
            attr = attributes[rule.to]
            raise "Attribute '#{rule.to}' not found in #{self}" unless attr

            value = doc[rule.name]
            if attr.collection?
              value = (value || []).map { |v| attr.type <= Serialize ? attr.type.from_hash(v) : v }
            elsif value.is_a?(Hash) && attr.type <= Serialize
              value = attr.type.cast(value)
            elsif value.is_a?(Array)
              value = attr.type.cast(value.first["text"].first)
            end
            hash[rule.to] = value
          end
        end

        def apply_content_mapping(doc, mapped_attrs)
          content_mapping = mappings_for(:xml).content_mapping
          return unless content_mapping

          content = doc.root.children.select(&:text?).map(&:text)
          mapped_attrs[content_mapping.to] = content
        end
      end

      def initialize(attrs = {})
        return self unless self.class.attributes

        self.class.attributes.each do |name, attr|
          value = if attrs.key?(name)
                    attrs[name]
                  elsif attrs.key?(name.to_sym)
                    attrs[name.to_sym]
                  elsif attrs.key?(name.to_s)
                    attrs[name.to_s]
                  else
                    attr.default
                  end

          value = if attr.collection?
              (value || []).map { |v| Lutaml::Model::Type.cast(v, attr.type) }
            else
              Lutaml::Model::Type.cast(value, attr.type)
            end
          send("#{name}=", ensure_utf8(value))
        end
      end

      # TODO: Make this work
      # FORMATS.each do |format|
      #   define_method("to_#{format}") do |options = {}|
      #     adapter = Lutaml::Model::Config.send("#{format}_adapter")
      #     representation = format == :yaml ? self : hash_representation(format, options)
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

          value = send(name)
          next if value.nil? && !rule.render_nil

          attribute = self.class.attributes[name]
          hash[rule.from] = case value
            when Array
              value.map { |v| v.is_a?(Serialize) ? v.hash_representation(format, options) : attribute.type.serialize(v) }
            else
              value.is_a?(Serialize) ? value.hash_representation(format, options) : attribute.type.serialize(value)
            end
        end
      end

      private

      def ensure_utf8(value)
        case value
        when String
          value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        when Array
          value.map { |v| ensure_utf8(v) }
        when Hash
          value.transform_keys { |k| ensure_utf8(k) }.transform_values { |v| ensure_utf8(v) }
        else
          value
        end
      end
    end
  end
end
