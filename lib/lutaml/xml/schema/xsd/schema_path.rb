# frozen_string_literal: true

require "net/http"

module Lutaml
  module Xml
    module Schema
      module Xsd
        class SchemaPath
          URI_SCHEMES = %w[http https].freeze
          WINDOWS_ABSOLUTE_PATH_REGEX = %r{\A[A-Za-z]:[\\/]}
          FORWARD_SLASH = "/"

          attr_reader :location, :path, :url, :schema_mappings

          def initialize(location, schema_mappings: [])
            @location = location
            @schema_mappings = normalize_mappings(schema_mappings)
            assign_location(location)
          end

          def path?
            !path.nil?
          end

          def url?
            !url.nil?
          end

          def location?
            path? || url?
          end

          def include_schema(schema_location)
            return unless schema_location

            resolved_location = resolve_schema_location(schema_location)
            if absolute_path?(resolved_location)
              return read_absolute_path(
                resolved_location,
                schema_location,
                mapped: resolved_location != schema_location,
              )
            end
            return http_get(resolved_location) if absolute_url?(resolved_location)

            schema_path = schema_location_path(resolved_location)
            url? ? http_get(schema_path) : read_absolute_path(schema_path, schema_location)
          end

          def location_for(schema_location)
            resolved_location = resolve_schema_location(schema_location)
            return resolved_location if absolute_path?(resolved_location) || absolute_url?(resolved_location)

            schema_location_path(resolved_location)
          end

          def relative_path?(schema_location)
            return false unless location? && schema_location

            resolved_location = resolve_schema_location(schema_location)
            return false if absolute_path?(resolved_location) || absolute_url?(resolved_location)

            File.exist?(schema_location_path(resolved_location))
          end

          def schema_location_path(schema_location)
            if url?
              separator = FORWARD_SLASH unless url_separator_present?(schema_location)
              [url.to_s, schema_location].compact.join(separator)
            else
              File.join([path, schema_location].compact)
            end
          end

          def resolve_schema_location(schema_location)
            return schema_location if schema_location.nil?
            return schema_location if schema_mappings.empty?

            schema_location_candidates(schema_location).each do |candidate|
              mapped = mapped_schema_location(candidate)
              return mapped if mapped
            end

            schema_location
          end

          def absolute_path?(path)
            path.to_s.start_with?(FORWARD_SLASH) ||
              path.to_s.match?(WINDOWS_ABSOLUTE_PATH_REGEX)
          end

          def absolute_url?(schema_location)
            URI::DEFAULT_PARSER
              .make_regexp(URI_SCHEMES)
              .match?(schema_location.to_s)
          end

          private

          def assign_location(location)
            if absolute_url?(location)
              @url = URI(extract_base_url(location))
            elsif location
              expanded = File.expand_path(location)
              @path = File.directory?(expanded) ? expanded : File.dirname(expanded)
            end
          rescue Errno::ENOENT
            raise ::Lutaml::Xml::Schema::Xsd::Error,
                  "Invalid location: #{location}"
          end

          def normalize_mappings(mappings)
            return [] if mappings.nil? || mappings == {}

            Array(mappings)
          end

          def schema_location_candidates(schema_location)
            candidates = [schema_location]
            case schema_location
            when /\Ahttp:\/\//
              candidates << schema_location.sub(/\Ahttp:\/\//, "https://")
            when /\Ahttps:\/\//
              candidates << schema_location.sub(/\Ahttps:\/\//, "http://")
            end
            candidates.uniq
          end

          def mapped_schema_location(schema_location)
            schema_mappings.each do |mapping|
              from = mapping[:from] || mapping["from"]
              to = mapping[:to] || mapping["to"]
              pattern = mapping[:pattern] || mapping["pattern"]
              next unless from && to

              if pattern != true && from.is_a?(String) && from == schema_location
                return to
              end

              next unless pattern == true || from.is_a?(Regexp)

              regex = from.is_a?(Regexp) ? from : Regexp.new(from)
              return schema_location.gsub(regex, to) if schema_location.match?(regex)
            end

            nil
          end

          def read_absolute_path(path, original_location, mapped: false)
            unless File.exist?(path)
              message = mapped ? "Mapped schema file not found" : "Schema file not found"
              raise ::Lutaml::Xml::Schema::Xsd::Error,
                    "#{message}: #{path} " \
                    "(original location: #{original_location})"
            end

            File.read(path)
          end

          def http_get(uri)
            Net::HTTP.get(URI.parse(uri))
          end

          def extract_base_url(uri)
            parsed_uri = URI.parse(uri.to_s)
            path = parsed_uri.path.to_s
            last_separator_index = path.rindex(FORWARD_SLASH)
            return uri unless last_separator_index

            last_segment = path[(last_separator_index + 1)..]
            return uri unless last_segment&.include?(".")

            parsed_uri.path = path[0..last_separator_index]
            parsed_uri.query = nil
            parsed_uri.fragment = nil
            parsed_uri.to_s
          end

          def url_separator_present?(schema_location)
            schema_location&.start_with?(FORWARD_SLASH) ||
              url.to_s.end_with?(FORWARD_SLASH)
          end
        end
      end
    end
  end
end
