module Lutaml
  module Model
    class FormatRegistry
      class << self
        attr_reader :format, :mapping_class, :adapter_class

        def register(format, mapping_class:, adapter_class:, transformer:)
          registered_formats[format] = {
            mapping_class: mapping_class,
            transformer: transformer,
          }

          ::Lutaml::Model::Type::Value.register_format_to_from_methods(format)
          ::Lutaml::Model::Serialize.register_format_mapping_method(format)
          ::Lutaml::Model::Serialize.register_from_format_method(format)
          ::Lutaml::Model::Serialize.register_to_format_method(format)

          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter") do
            instance_variable_get(:"@#{format}_adapter") || adapter_class
          end

          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter=") do |adapter_klass|
            instance_variable_set(:"@#{format}_adapter", adapter_klass)
          end
        end

        def mappings_class_for(format)
          registered_formats.dig(format, :mapping_class)
        end

        def transformer_for(format)
          registered_formats.dig(format, :transformer)
        end

        def registered_formats
          @registered_formats ||= {}
        end
      end
    end
  end
end
