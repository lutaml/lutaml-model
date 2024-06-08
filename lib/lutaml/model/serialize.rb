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
            new(mapped_attrs)
          end
        end

        def mappings_for(format)
          self.mappings[format] || default_mappings(format)
        end

        def default_mappings(format)
          klass = format == :xml ? XmlMapping : KeyValueMapping
          klass.new.tap do |mapping|
            attributes.each do |name, attr|
              mapping.map_element(name.to_s, to: name, render_nil: attr.render_nil?)
            end
          end
        end

        def apply_mappings(doc, format)
          mappings = mappings_for(format).mappings
          mappings.each_with_object({}) do |rule, hash|
            value = doc[rule.name]
            if attributes[rule.to].collection?
              value = (value || []).map { |v| attributes[rule.to].type <= Serializable ? attributes[rule.to].type.new(v) : v }
            elsif value.is_a?(Hash) && attributes[rule.to].type <= Serializable
              value = attributes[rule.to].type.new(value)
            end
            hash[rule.to] = value
          end
        end
      end

      def initialize(attrs = {})
        return self unless self.class.attributes

        self.class.attributes.each do |name, attr|
          value = attrs.key?(name) ? attrs[name] : attr.default
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

          hash[rule.from] = case value
            when Array
              value.map { |v| v.is_a?(Serializable) ? v.hash_representation(format, options) : v }
            else
              value.is_a?(Serializable) ? value.hash_representation(format, options) : value
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
