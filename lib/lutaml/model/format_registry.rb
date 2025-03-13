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

          define_singleton_method(:"#{format}_adapter") do
            instance_variable_get(:"@#{format}_adapter") || adapter_class
          end

          define_singleton_method(:"#{format}_adapter=") do |adapter_klass|
            instance_variable_set(:"@#{format}_adapter", adapter_klass)
          end
        end

        def adapter_for(format)
          public_send(:"#{format}_adapter")
        end

        def set_adapter_for(format, adapter)
          public_send(:"#{format}_adapter=", adapter)
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

        Lutaml::Model::Config::AVAILABLE_FORMATS.each do |adapter_name|
          define_method(:"#{adapter_name}_adapter_type=") do |type_name|
            adapter = if %i[json yaml toml].include?(adapter_name)
                        adapter_name.to_s
                      else
                        "#{adapter_name}_adapter"
                      end

            type = if %i[json yaml toml].include?(adapter_name)
                     "#{type_name.to_s.gsub("_#{adapter_name}", '')}_adapter"
                   else
                     "#{type_name}_adapter"
                   end
            begin
              adapter_file = File.join(adapter, type)
              require_relative adapter_file
            rescue LoadError
              require "pry"
              binding.pry
              raise(
                Lutaml::Model::UnknownAdapterTypeError.new(
                  adapter_name,
                  type_name,
                ),
                cause: nil,
              )
            end
            Moxml::Adapter.load(type_name) unless Lutaml::Model::Config::KEY_VALUE_FORMATS.include?(adapter_name)

            set_adapter_for(adapter_name, class_for(adapter, type))
          end
        end

        private

        def to_class_name(str)
          str.to_s.split("_").map(&:capitalize).join
        end

        def class_for(adapter, type)
          Lutaml::Model.const_get(to_class_name(adapter))
                       .const_get(to_class_name(type))
        end
      end
    end
  end
end
