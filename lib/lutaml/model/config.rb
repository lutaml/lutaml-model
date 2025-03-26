module Lutaml
  module Model
    module Config
      extend self

      # Default values are set for these so the readers are defined below
      attr_writer :json_adapter, :yaml_adapter, :hash_adapter

      attr_accessor :xml_adapter, :toml_adapter

      %i[
        hash_adapter 
        json_adapter 
        yaml_adapter 
        xml_adapter 
        toml_adapter
      ].each do |method_name|
        define_method(method_name) do
          Lutaml::Model::FormatRegistry.send(method_name)
        end

        define_method(:"#{method_name}=") do |adapter|
          Lutaml::Model::FormatRegistry.send(:"#{method_name}=", adapter)
        end
      end

      AVAILABLE_FORMATS = %i[xml json yaml toml hash].freeze
      KEY_VALUE_FORMATS = AVAILABLE_FORMATS - %i[xml]

      def configure
        yield self
      end

      # This will generate the following methods
      #
      # xml_adapter_type=
      #   @params:
      #     one of [:nokogiri, :ox, :oga]
      #   @example
      #     Lutaml::Model::Config.xml_adapter = :nokogiri
      #
      # json_adapter_type=
      #   @params:
      #     one of [:standard_json, :multi_json]
      #     if not set, :standard_json will be used by default
      #   @example
      #     Lutaml::Model::Config.json_adapter = :standard_json
      #
      # yaml_adapter_type=
      #   @params:
      #     one of [:standard_yaml]
      #     if not set, :standard_yaml will be used by default
      #   @example
      #     Lutaml::Model::Config.yaml_adapter = :standard_yaml
      #
      # toml_adapter_type=
      #   @params
      #     one of [:tomlib, :toml_rb]
      #   @example
      #     Lutaml::Model::Config.toml_adapter = :tomlib
      #
      AVAILABLE_FORMATS.each do |adapter_name|
        define_method(:"#{adapter_name}_adapter_type=") do |type_name|
          Lutaml::Model::FormatRegistry.send(:"#{adapter_name}_adapter_type=", type_name)
        end
      end

      # Return JSON adapter. By default StandardJsonAdapter is used
      #
      # @example
      #   Lutaml::Model::Config.json_adapter
      #   # => Lutaml::Model::YamlAdapter::StandardJsonAdapter
      # def json_adapter
      #   @json_adapter || Lutaml::Model::JsonAdapter::StandardJsonAdapter
      # end

      # Return YAML adapter. By default StandardYamlAdapter is used
      #
      # @example
      #   Lutaml::Model::Config.yaml_adapter
      #   # => Lutaml::Model::YamlAdapter::StandardYamlAdapter
      # def yaml_adapter
      #   @yaml_adapter || Lutaml::Model::YamlAdapter::StandardYamlAdapter
      # end

      # Return Hash adapter. By default StandardHashAdapter is used
      #
      # @example
      # Lutaml::Model::Config.hash_adapter
      # # => Lutaml::Model::HashAdapter::StandardHashAdapter
      # def hash_adapter
      #   @hash_adapter || Lutaml::Model::HashAdapter::StandardAdapter
      # end

      # @api private
      def to_class_name(str)
        str.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
