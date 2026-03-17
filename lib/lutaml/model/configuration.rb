# frozen_string_literal: true

module Lutaml
  module Model
    # Single source of truth for Lutaml::Model configuration
    #
    # @example Basic configuration
    #   Lutaml::Model::Configuration.configure do |config|
    #     config.xml_adapter = :nokogiri
    #     config.json_adapter = :standard
    #     config.toml_adapter = :toml_rb
    #   end
    #
    class Configuration
      AVAILABLE_FORMATS = %i[xml json jsonl yaml toml hash].freeze
      KEY_VALUE_FORMATS = AVAILABLE_FORMATS - %i[xml]

      # Available formats and their adapters
      ADAPTERS = begin
        h = {
          xml: {
            available: %i[nokogiri ox oga rexml],
            default: :nokogiri,
          },
          json: {
            available: %i[standard standard_json multi_json oj],
            default: :standard,
          },
          yaml: {
            available: %i[standard standard_yaml],
            default: :standard,
          },
          toml: {
            available: %i[tomlib toml_rb],
            default: Gem.win_platform? ? :toml_rb : :tomlib,
          },
          hash: {
            available: %i[standard standard_hash],
            default: :standard,
          },
          jsonl: {
            available: %i[standard],
            default: :standard,
          },
          yamls: {
            available: %i[standard],
            default: :standard,
          },
        }
        h.freeze
      end

      attr_reader :adapter_types

      def initialize
        @adapter_types = {}
        @adapters = {}
        @default_register = :default
        @configured = false
      end

      # Configure the library using a block
      def configure
        yield self if block_given?
        @configured = true
        self
      end

      def configured?
        @configured
      end

      # Check if running on Windows platform
      def self.windows_platform?
        Gem.win_platform?
      end

      # Dynamic accessor for adapter types
      def adapter_for(format)
        @adapter_types[format.to_sym]
      end

      # Dynamic setter for adapter types with validation
      def set_adapter(format, adapter_type)
        format = format.to_sym
        adapter_type = adapter_type.to_sym

        validate_adapter!(format, adapter_type)
        @adapter_types[format] = adapter_type

        # Load the adapter immediately
        load_adapter(format, adapter_type)
      end

      # Define dynamic accessor methods for each format
      ADAPTERS.each_key do |format|
        # Getter method: config.xml_adapter
        define_method(:"#{format}_adapter") do
          @adapter_types[format] || ADAPTERS[format][:default]
        end

        # Setter method: config.xml_adapter = :nokogiri
        define_method(:"#{format}_adapter=") do |adapter_type|
          set_adapter(format, adapter_type)
        end

        # Aliased setter with _type suffix: config.xml_adapter_type = :nokogiri
        alias_method :"#{format}_adapter_type=", :"#{format}_adapter="
        alias_method :"#{format}_adapter_type", :"#{format}_adapter"
      end

      # Default register/context ID accessor
      attr_reader :default_register

      def default_register=(value)
        @default_register = case value
                            when Symbol then value
                            when Lutaml::Model::Register then value.id
                            else
                              raise ArgumentError,
                                    "Unknown register: #{value.inspect}. " \
                                    "Expected a Symbol or a Lutaml::Model::Register instance."
                            end
      end

      # Alias for terminology alignment
      alias default_context_id default_register
      alias default_context_id= default_register=

      # Get adapter class for a format
      def get_adapter(format)
        @adapters[format.to_sym]
      end

      # Reset configuration to defaults
      def reset!
        @adapter_types = {}
        @adapters = {}
        @default_register = :default
        @configured = false
      end

      # Get all current settings as a hash
      def to_h
        {
          adapter_types: @adapter_types.dup,
          default_register: @default_register,
          configured: @configured,
        }
      end

      # Mappings class for a format
      def mappings_class_for(format)
        Lutaml::Model::FormatRegistry.mappings_class_for(format)
      end

      # Transformer for a format
      def transformer_for(format)
        Lutaml::Model::FormatRegistry.transformer_for(format)
      end

      private

      # Validate that the adapter is available for the format
      def validate_adapter!(format, adapter_type)
        unless ADAPTERS.key?(format)
          available_formats = ADAPTERS.keys.map { |f| "`:#{f}`" }.join(", ")
          raise ArgumentError,
                "Unknown format: `:#{format}`. Available formats: #{available_formats}."
        end

        # Check for Windows + tomlib incompatibility
        if format == :toml && adapter_type == :tomlib && self.class.windows_platform?
          raise ArgumentError,
                "The `:tomlib` adapter is not supported on Windows due to " \
                "segmentation fault issues. Please use `:toml_rb` instead."
        end

        available = ADAPTERS[format][:available]
        return if available.include?(adapter_type)

        available_list = available.map { |a| "`:#{a}`" }.join(", ")
        closest = find_suggestion(adapter_type.to_s, available.map(&:to_s))

        msg = "Unknown adapter: `:#{adapter_type}` for `:#{format}` format. " \
              "Available adapters: #{available_list}."
        msg += " Did you mean `:#{closest}`?" if closest

        raise ArgumentError, msg
      end

      # Load an adapter for a format
      def load_adapter(format, adapter_type)
        adapter = format.to_s
        type = normalize_type_name(adapter_type, format)

        load_adapter_file(adapter, type)
        load_moxml_adapter(adapter_type, format)

        adapter_class = class_for(adapter, type)
        @adapters[format] = adapter_class

        # Also set in Config's adapters for FormatRegistry compatibility
        Config.set_adapter_for(format, adapter_class)
      end

      def normalize_type_name(type_name, adapter_name)
        if type_name.to_s.start_with?('multi_json')
          'multi_json_adapter'
        else
          "#{type_name.to_s.gsub("_#{adapter_name}", '')}_adapter"
        end
      end

      def load_adapter_file(adapter, type)
        adapter_path = if adapter == "xml"
                         File.join(__dir__, "../xml/adapter", type)
                       else
                         File.join(__dir__, "../key_value/adapter", adapter, type)
                       end
        require adapter_path
      rescue LoadError
        raise UnknownAdapterTypeError.new(adapter, type), cause: nil
      end

      def load_moxml_adapter(type_name, adapter_name)
        return if KEY_VALUE_FORMATS.include?(adapter_name)

        Moxml::Adapter.load(type_name)
      end

      def class_for(adapter, type)
        if adapter == "xml"
          Lutaml::Xml::Adapter.const_get(to_class_name(type))
        else
          Lutaml::KeyValue::Adapter.const_get(to_class_name(adapter))
            .const_get(to_class_name(type))
        end
      end

      def to_class_name(str)
        str.to_s.split("_").map(&:capitalize).join
      end

      # Find closest string match for suggestions
      def find_suggestion(input, candidates)
        return nil if input.nil? || input.empty?

        candidates.min_by do |candidate|
          levenshtein_distance(input.downcase, candidate.downcase)
        end.tap do |closest|
          max_dist = ([input.length, closest.length].max / 2) + 1
          return nil if closest && levenshtein_distance(input.downcase,
                                                        closest.downcase) > max_dist
        end
      end

      # Calculate Levenshtein distance between two strings
      def levenshtein_distance(a, b)
        return a.length if b.empty?
        return b.length if a.empty?

        matrix = Array.new(a.length + 1) do |i|
          Array.new(b.length + 1) do |j|
            if i.zero?
              j
            else
              (j.zero? ? i : 0)
            end
          end
        end

        (1..a.length).each do |i|
          (1..b.length).each do |j|
            cost = a[i - 1] == b[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,
              matrix[i][j - 1] + 1,
              matrix[i - 1][j - 1] + cost,
            ].min
          end
        end

        matrix[a.length][b.length]
      end
    end
  end
end
