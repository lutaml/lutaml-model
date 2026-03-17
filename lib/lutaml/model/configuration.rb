# frozen_string_literal: true

module Lutaml
  module Model
    # Configuration class for Lutaml::Model settings
    #
    # This class provides a structured way to configure Lutaml::Model with
    # validation and type safety. It replaces the module-based Config approach
    # with a proper configuration object pattern.
    #
    # @example Basic configuration
    #   Lutaml::Model::Configuration.configure do |config|
    #     config.xml_adapter = :nokogiri
    #     config.json_adapter = :standard
    #     config.default_register = :my_app
    #   end
    #
    # @example With validation
    #   config = Lutaml::Model::Configuration.new
    #   config.xml_adapter = :nokogiri  # => :nokogiri
    #   config.xml_adapter = :invalid   # => raises ConfigurationError
    #
    class Configuration
      # Available formats and their adapters
      ADAPTERS = {
        xml: {
          available: %i[nokogiri ox oga rexml],
          default: :nokogiri,
        },
        json: {
          available: %i[standard multi_json oj],
          default: :standard,
        },
        yaml: {
          available: %i[standard],
          default: :standard,
        },
        toml: {
          available: %i[tomlib toml_rb],
          default: windows_platform? ? :toml_rb : :tomlib,
        },
        hash: {
          available: %i[standard],
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
      }.freeze

      # Check if running on Windows platform
      #
      # @return [Boolean] true if on Windows
      def self.windows_platform?
        Gem.win_platform?
      end

      attr_reader :adapter_types

      def initialize
        @adapter_types = {}
        @default_register = :default
        @configured = false
      end

      # Configure the library using a block
      #
      # @yield [Configuration] self for configuration
      # @return [Configuration] self for method chaining
      #
      # @example
      #   config.configure do |c|
      #     c.xml_adapter = :ox
      #     c.json_adapter = :oj
      #   end
      def configure
        yield self if block_given?
        @configured = true
        apply_adapters!
        self
      end

      # Check if configuration has been applied
      #
      # @return [Boolean]
      def configured?
        @configured
      end

      # Dynamic accessor for adapter types
      #
      # @param format [Symbol] the format name (e.g., :xml, :json)
      # @return [Symbol, nil] the configured adapter type
      def adapter_for(format)
        @adapter_types[format.to_sym]
      end

      # Dynamic setter for adapter types
      #
      # @param format [Symbol] the format name
      # @param adapter_type [Symbol] the adapter type
      # @raise [ConfigurationError] if adapter is not available
      def set_adapter(format, adapter_type)
        format = format.to_sym
        adapter_type = adapter_type.to_sym

        validate_adapter!(format, adapter_type)
        @adapter_types[format] = adapter_type
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
      end

      # Default register/context ID accessor
      #
      # @return [Symbol] the default register ID
      attr_reader :default_register

      # Set the default register
      #
      # @param value [Symbol, Register] the register or its ID
      # @raise [ArgumentError] if value is invalid
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

      # Reset configuration to defaults
      #
      # @return [void]
      def reset!
        @adapter_types = {}
        @default_register = :default
        @configured = false
      end

      # Get all current settings as a hash
      #
      # @return [Hash] current configuration settings
      def to_h
        {
          adapter_types: @adapter_types.dup,
          default_register: @default_register,
          configured: @configured,
        }
      end

      private

      # Validate that the adapter is available for the format
      #
      # @param format [Symbol] the format name
      # @param adapter_type [Symbol] the adapter type
      # @raise [ArgumentError] if adapter is not available
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

      # Apply configured adapters to the legacy Config module
      #
      # This ensures backward compatibility with the existing configuration system
      def apply_adapters!
        @adapter_types.each do |format, adapter_type|
          # Delegate to the legacy Config module for now
          # This will be simplified once full migration is complete
          Config.send(:"#{format}_adapter_type=", adapter_type)
        end

        Config.default_register = @default_register if @default_register != :default
      end

      # Find closest string match for suggestions
      #
      # @param input [String] the input string
      # @param candidates [Array<String>] possible matches
      # @return [String, nil] the closest match or nil
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
