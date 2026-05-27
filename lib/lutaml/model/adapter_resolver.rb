# frozen_string_literal: true

module Lutaml
  module Model
    # Single authority for adapter resolution: (format, type_name) → adapter class.
    #
    # Consolidates adapter metadata, loading, validation, and auto-detection
    # that was previously spread across Config, Configuration, and FormatRegistry.
    #
    # Resolution chain (in order):
    #   1. Thread-local AdapterScope override
    #   2. Explicitly configured type (from Config.xml_adapter_type =)
    #   3. Lazy auto-detected type (cached after first probe)
    #   4. Default from format metadata
    #   5. Raise FormatAdapterNotSpecifiedError
    #
    # @example Configure an adapter
    #   AdapterResolver.set_adapter_type(:xml, :nokogiri)
    #
    # @example Resolve an adapter
    #   adapter_class = AdapterResolver.adapter_for(:xml)
    #
    # @example Per-operation override
    #   adapter_class = AdapterResolver.resolved_adapter_class(:xml, :ox)
    #
    class AdapterResolver
      class << self
        # --- Resolution ---

        # Resolve the adapter class for a format using the full resolution chain.
        #
        # @param format [Symbol] the format name (:xml, :json, etc.)
        # @return [Class, nil] the adapter class or nil
        def adapter_for(format)
          # 1. Thread-local scope override
          scope_override = AdapterScope.override_for(format)
          if scope_override
            return resolved_adapter_class(format, scope_override)
          end

          # 2. Explicitly configured type
          configured = configured_type(format)
          if configured
            adapter = resolved[format]
            return adapter if adapter
          end

          # 3. Lazy auto-detection (cached)
          detected = detected_types[format]
          if detected.nil? && !detected_formats.key?(format)
            result = detect_adapter_for(format)
            if result
              detected_formats[format] = true
              detected_types[format] = result
              return load_and_cache(format, result)
            end
            detected_formats[format] = true
          elsif detected
            return load_and_cache(format, detected)
          end

          # 4. Default from metadata
          default = metadata.dig(format, :default)
          if default
            return load_and_cache(format, default)
          end

          # 5. No adapter available
          nil
        end

        # Set the adapter type for a format (validates and loads).
        #
        # @param format [Symbol] the format name
        # @param type_name [Symbol] the adapter type name (:nokogiri, :ox, etc.)
        # @return [Class] the loaded adapter class
        def set_adapter_type(format, type_name)
          type_name = type_name.to_sym
          validate!(format, type_name)
          configured_types[format] = type_name
          resolved[format] = load_adapter(format, type_name)
        end

        # Store a pre-resolved adapter class for a format.
        #
        # Used by FormatRegistry.register for key-value formats that have
        # a fixed adapter class (not selectable by type name).
        #
        # @param format [Symbol] the format name
        # @param adapter_class [Class] the adapter class
        # @return [void]
        def set_adapter_class(format, adapter_class)
          resolved[format] = adapter_class
          configured_types[format] = :__fixed__
        end

        # Load and resolve an adapter class by type name.
        # Used for per-operation overrides (from_xml adapter: :ox).
        #
        # @param format [Symbol] the format name
        # @param type_name [Symbol, String] the adapter type name
        # @return [Class] the adapter class
        def resolved_adapter_class(format, type_name)
          type_name = type_name.to_sym
          validate!(format, type_name)
          load_adapter(format, type_name)
        end

        # --- Metadata Registration ---

        # Register adapter metadata for a format (available adapters, default).
        #
        # Called by FormatRegistry.register for formats with selectable adapters.
        #
        # @param format [Symbol] the format name
        # @param options [Hash] { available: [...], default: :name }
        # @return [void]
        def register_metadata(format, options)
          metadata[format] = options
        end

        # Register a fixed adapter class for a format with a single adapter.
        #
        # Used for key-value formats (json, yaml, hash, etc.) that have
        # exactly one adapter. Creates metadata so validation works.
        #
        # @param format [Symbol] the format name
        # @param adapter_class [Class] the adapter class
        # @param adapter_name [Symbol] the adapter type name (e.g., :standard)
        # @return [void]
        def register_fixed(format, adapter_class, adapter_name)
          metadata[format] = {
            available: [adapter_name],
            default: adapter_name,
          }
          resolved[format] = adapter_class
          configured_types[format] = adapter_name
        end

        # Get the configured type name for a format.
        #
        # @param format [Symbol] the format name
        # @return [Symbol, nil] the type name or nil
        def configured_type(format)
          configured_types[format]
        end

        # --- Reset ---

        # Clear all state (for testing reset).
        #
        # @return [void]
        def reset!
          @metadata = nil
          @configured_types = nil
          @resolved = nil
          @detected_types = nil
          @detected_formats = nil
        end

        private

        # Internal state accessors

        def metadata
          @metadata ||= {}
        end

        def configured_types
          @configured_types ||= {}
        end

        def resolved
          @resolved ||= {}
        end

        def detected_types
          @detected_types ||= {}
        end

        def detected_formats
          @detected_formats ||= {}
        end

        # Load adapter and cache the result.
        #
        # @param format [Symbol] the format name
        # @param type_name [Symbol] the adapter type name
        # @return [Class] the adapter class
        def load_and_cache(format, type_name)
          resolved[format] ||= load_adapter(format, type_name)
        end

        # Load an adapter file and resolve to its class.
        #
        # @param format [Symbol] the format name
        # @param type_name [Symbol] the adapter type name
        # @return [Class] the adapter class
        def load_adapter(format, type_name)
          adapter = format.to_s
          type = normalize_type_name(type_name, format)

          load_adapter_file(adapter, type)
          load_moxml_adapter(type_name, format)

          class_for(adapter, type)
        end

        # Normalize type name to file/class name pattern.
        #
        # @param type_name [Symbol] raw type name
        # @param format [Symbol] format name
        # @return [String] normalized type name (e.g., "nokogiri_adapter")
        def normalize_type_name(type_name, format)
          if type_name.to_s.start_with?("multi_json")
            "multi_json_adapter"
          else
            "#{type_name.to_s.gsub("_#{format}", '')}_adapter"
          end
        end

        # Load the adapter file.
        #
        # @param adapter [String] format name as string
        # @param type [String] normalized type name
        def load_adapter_file(adapter, type)
          loader = FormatRegistry.adapter_loader_for(adapter.to_sym)
          if loader
            loader.load_adapter_file(adapter, type)
            return
          end

          # Default key-value adapter loading
          adapter_path = if RuntimeCompatibility.opal?
                           "lutaml/key_value/adapter/#{adapter}/#{type}"
                         else
                           File.join(File.dirname(__FILE__), "../key_value/adapter",
                                     adapter, type)
                         end
          require adapter_path
        rescue LoadError
          raise UnknownAdapterTypeError.new(adapter, type), cause: nil
        end

        # Load the Moxml adapter for XML and similar formats.
        #
        # @param type_name [Symbol] raw type name
        # @param format [Symbol] format name
        def load_moxml_adapter(type_name, format)
          loader = FormatRegistry.adapter_loader_for(format)
          loader&.load_moxml_adapter(type_name,
                                     format)
        end

        # Resolve the adapter class from the type name.
        #
        # @param adapter [String] format name as string
        # @param type [String] normalized type name
        # @return [Class] the adapter class
        def class_for(adapter, type)
          loader = FormatRegistry.adapter_loader_for(adapter.to_sym)
          if loader
            return loader.class_for(adapter, type)
          end

          # Default key-value adapter class resolution
          KeyValue::Adapter.const_get(to_class_name(adapter))
            .const_get(to_class_name(type))
        end

        # Validate that the adapter type is available for the format.
        #
        # @param format [Symbol] the format name
        # @param type_name [Symbol] the adapter type name
        # @raise [ArgumentError] if format or adapter is unknown
        def validate!(format, type_name)
          adapter_config = metadata[format]

          unless adapter_config
            all_formats = metadata.keys
            available_formats = all_formats.map { |f| "`:#{f}`" }.join(", ")
            raise ArgumentError,
                  "Unknown format: `:#{format}`. Available formats: #{available_formats}."
          end

          if format == :toml && type_name == :tomlib && RuntimeCompatibility.windows?
            raise ArgumentError,
                  "The `:tomlib` adapter is not supported on Windows due to " \
                  "segmentation fault issues. Please use `:toml_rb` instead."
          end

          available = adapter_config[:available]
          return unless available
          return if available.include?(type_name)

          available_list = available.map { |a| "`:#{a}`" }.join(", ")
          closest = find_suggestion(type_name.to_s, available.map(&:to_s))

          msg = "Unknown adapter: `:#{type_name}` for `:#{format}` format. " \
                "Available adapters: #{available_list}."
          msg += " Did you mean `:#{closest}`?" if closest

          raise ArgumentError, msg
        end

        # Find closest string match for suggestions.
        #
        # @param input [String]
        # @param candidates [Array<String>]
        # @return [String, nil]
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

        # Calculate Levenshtein distance.
        #
        # @param lhs [String]
        # @param rhs [String]
        # @return [Integer]
        def levenshtein_distance(lhs, rhs)
          return lhs.length if rhs.empty?
          return rhs.length if lhs.empty?

          matrix = Array.new(lhs.length + 1) do |i|
            Array.new(rhs.length + 1) do |j|
              if i.zero?
                j
              else
                (j.zero? ? i : 0)
              end
            end
          end

          (1..lhs.length).each do |i|
            (1..rhs.length).each do |j|
              cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
              matrix[i][j] = [
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost,
              ].min
            end
          end

          matrix[lhs.length][rhs.length]
        end

        # Auto-detect available adapter for a format.
        #
        # @param format [Symbol] the format name
        # @return [Symbol, nil] the detected adapter type name
        def detect_adapter_for(format)
          case format
          when :xml
            detect_xml_adapter
          when :toml
            detect_toml_adapter
          else
            metadata.dig(format, :default)
          end
        end

        # Detect available XML adapter.
        #
        # Delegates to moxml which is the authority on XML adapter
        # availability and platform constraints (Opal, MRI, etc.).
        #
        # @return [Symbol] adapter type name
        def detect_xml_adapter
          Moxml::Config.runtime_default_adapter
        end

        # Detect available TOML adapter.
        #
        # @return [Symbol, nil] :tomlib, :toml_rb, or nil
        def detect_toml_adapter
          return nil if RuntimeCompatibility.opal?

          if RuntimeCompatibility.windows?
            return :toml_rb if Utils.safe_load("toml-rb", :TomlRb)

            return nil
          end

          return :tomlib if Utils.safe_load("tomlib", :Tomlib)
          return :toml_rb if Utils.safe_load("toml-rb", :TomlRb)

          nil
        end

        def to_class_name(str)
          str.to_s.split("_").map(&:capitalize).join
        end
      end
    end
  end
end
