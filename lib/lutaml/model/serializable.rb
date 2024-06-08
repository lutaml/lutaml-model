# lib/lutaml/model/serializable.rb
require "json"
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
    class Serializable
      def self.attributes
        @attributes ||= {}
      end

      def self.attribute(name, type, options = {})
        attr = Attribute.new(name, type, options)
        attributes[name] = attr

        if attr.collection?
          define_method(name) do
            instance_variable_get("@#{name}") || instance_variable_set("@#{name}", [])
          end

          define_method("#{name}=") do |value|
            instance_variable_set("@#{name}", value || [])
          end
        else
          attr_accessor name
        end
      end

      def self.xml(&block)
        @xml_mappings = XmlMapping.new
        @xml_mappings.instance_eval(&block) if block_given?
      end

      def self.yaml(&block)
        @yaml_mappings = KeyValueMapping.new
        @yaml_mappings.instance_eval(&block) if block_given?
      end

      def self.toml(&block)
        @toml_mappings = KeyValueMapping.new
        @toml_mappings.instance_eval(&block) if block_given?
      end

      def self.json(&block)
        @json_mappings = KeyValueMapping.new
        @json_mappings.instance_eval(&block) if block_given?
      end

      def self.xml_mappings
        @xml_mappings || default_xml_mappings
      end

      def self.yaml_mappings
        @yaml_mappings || default_key_value_mappings
      end

      def self.toml_mappings
        @toml_mappings || default_key_value_mappings
      end

      def self.json_mappings
        @json_mappings || default_key_value_mappings
      end

      def initialize(attrs = {})
        self.class.attributes.each do |name, attr|
          value = attrs.key?(name) ? attrs[name] : attr.default
          if attr.collection?
            value = (value || []).map { |v| Lutaml::Model::Type.cast(v, attr.type) }
          else
            value = Lutaml::Model::Type.cast(value, attr.type)
          end

          send("#{name}=", ensure_utf8(value))
        end
      end

      def to_xml(options = {})
        adapter = Lutaml::Model::Config.xml_adapter
        adapter.new(self).to_xml(options)
      end

      def self.from_xml(xml)
        adapter = Lutaml::Model::Config.xml_adapter
        adapter.from_xml(xml, self)
      end

      def to_json(options = {})
        adapter = Lutaml::Model::Config.json_adapter
        adapter.new(hash_representation(:json, options)).to_json(options)
      end

      def self.from_json(json)
        adapter = Lutaml::Model::Config.json_adapter
        doc = adapter.parse(json)
        new(doc.to_h)
      end

      def to_yaml(options = {})
        adapter = Lutaml::Model::Config.yaml_adapter
        adapter.to_yaml(hash_representation(:yaml, options), options)
      end

      def self.from_yaml(yaml)
        adapter = Lutaml::Model::Config.yaml_adapter
        adapter.from_yaml(yaml, self)
      end

      def to_toml(options = {})
        adapter = Lutaml::Model::Config.toml_adapter
        adapter.new(hash_representation(:toml, options)).to_toml
      end

      def self.from_toml(toml)
        adapter = Lutaml::Model::Config.toml_adapter
        doc = adapter.parse(toml)
        new(doc.to_h)
      end

      def hash_representation(format, options = {})
        only = options[:only]
        except = options[:except]

        mappings = case format
          when :json then self.class.json_mappings.mappings
          when :yaml then self.class.yaml_mappings.mappings
          when :toml then self.class.toml_mappings.mappings
          else raise ArgumentError, "Unsupported format: #{format}"
          end

        mappings.each_with_object({}) do |rule, hash|
          name = rule.to
          next if except&.include?(name)
          next if only && !only.include?(name)

          value = send(name)
          if value.nil? && !rule.render_nil
            next
          elsif value.is_a?(Array)
            hash[rule.from] = value.map { |v| v.is_a?(Serializable) ? v.hash_representation(format, options) : v }
          else
            hash[rule.from] = value.is_a?(Serializable) ? value.hash_representation(format, options) : value
          end
        end
      end

      private

      def ensure_utf8(value)
        if value.is_a?(String)
          value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        elsif value.is_a?(Array)
          value.map { |v| ensure_utf8(v) }
        elsif value.is_a?(Hash)
          value.transform_keys { |k| ensure_utf8(k) }.transform_values { |v| ensure_utf8(v) }
        else
          value
        end
      end

      def self.default_key_value_mappings
        proc do
          attributes.each do |name, attr|
            map name.to_s, to: name, render_nil: attr.render_nil?
          end
        end
      end

      def self.default_xml_mappings
        proc do
          root name.downcase
          attributes.each do |name, attr|
            map_element name.to_s, to: name, render_nil: attr.render_nil?
          end
        end
      end

      def self.apply_mappings(doc, mappings, model)
        mappings.each do |rule|
          if rule.delegate
            delegate_instance = model.send(rule.delegate)
            value = rule.deserialize(delegate_instance, doc)
            delegate_instance.send("#{rule.to}=", value)
          else
            value = rule.deserialize(model, doc)
            model.send("#{rule.to}=", value)
          end
        end
      end

      def self.from_document(doc, mappings)
        model = new
        apply_mappings(doc, mappings, model)
        model
      end
    end
  end
end
