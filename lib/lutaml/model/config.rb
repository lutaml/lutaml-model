module Lutaml
  module Model
    module Config
      extend self

      # Default values are set for these so the readers are defined below
      attr_writer :json_adapter, :yaml_adapter, :hash_adapter, :default_register

      attr_accessor :xml_adapter, :toml_adapter

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
      # AVAILABLE_FORMATS.each do |adapter_name|
      #   define_method(:"#{adapter_name}_adapter_type=") do |type_name|
      #     Lutaml::Model::FormatRegistry.send(:"#{adapter_name}_adapter_type=", type_name)
      #   end
      # end

      AVAILABLE_FORMATS.each do |adapter_name|
        define_method(:"#{adapter_name}_adapter_type=") do |type_name|
          adapter = adapter_name.to_s
          type = normalize_type_name(type_name, adapter_name)
          load_adapter_file(adapter, type)
          load_moxml_adapter(type_name, adapter_name)
          set_adapter_for(adapter_name, class_for(adapter, type))
        end
      end

      def adapter_for(format)
        public_send(:"#{format}_adapter")
      end

      def set_adapter_for(format, adapter)
        public_send(:"#{format}_adapter=", adapter)
      end

      def mappings_class_for(format)
        Lutaml::Model::FormatRegistry.mappings_class_for(format)
      end

      def transformer_for(format)
        Lutaml::Model::FormatRegistry.transformer_for(format)
      end

      def class_for(adapter, type)
        Lutaml::Model.const_get(to_class_name(adapter))
          .const_get(to_class_name(type))
      end

      def default_register
        @default_register ||= Lutaml::Model::Register.new(:default)
        Lutaml::Model::GlobalRegister.register(@default_register)
        @default_register
      end

      # @api private
      def to_class_name(str)
        str.to_s.split("_").map(&:capitalize).join
      end

      private

      def normalize_type_name(type_name, adapter_name)
        "#{type_name.to_s.gsub("_#{adapter_name}", '')}_adapter"
      end

      def load_adapter_file(adapter, type)
        adapter_file = File.join(adapter, type)
        require_relative adapter_file
      rescue LoadError
        raise UnknownAdapterTypeError.new(adapter, type), cause: nil
      end

      def load_moxml_adapter(type_name, adapter_name)
        return if KEY_VALUE_FORMATS.include?(adapter_name)

        Moxml::Adapter.load(type_name)
      end
    end
  end
end
