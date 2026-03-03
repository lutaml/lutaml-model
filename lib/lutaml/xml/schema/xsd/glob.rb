# frozen_string_literal: true

require "net/http"

module Lutaml
  module Xml
    module Schema
      module Xsd
        module Glob
          extend self

          def schema_mappings
            @schema_mappings ||= []
          end

          def schema_mappings=(mappings)
            @schema_mappings = mappings || []
          end

          def path_or_url(location)
            return nullify_location if location.nil?

            @location = location
            @url = location if location.start_with?(%r{http\w?:/{2}[^.]+})
            @path = File.expand_path(location) unless @url
          rescue Errno::ENOENT
            raise ::Lutaml::Xml::Schema::Xsd::Error, "Invalid location: #{location}"
          end

          def location
            @location
          end

          def path?
            !@path.nil?
          end

          def url?
            !@url.nil?
          end

          def location?
            url? || path?
          end

          def http_get(url)
            Net::HTTP.get(URI.parse(url))
          end

          def include_schema(schema_location)
            return unless location? && schema_location

            # Check if there's a mapping for this schema location
            resolved_location = resolve_schema_location(schema_location)

            # If resolved to absolute path, use it directly
            if absolute_path?(resolved_location)
              unless File.exist?(resolved_location)
                raise ::Lutaml::Xml::Schema::Xsd::Error, "Mapped schema file not found: #{resolved_location} " \
                                                         "(original location: #{schema_location})"
              end
              return File.read(resolved_location)
            end

            # If resolved location is a URL, fetch it directly
            return http_get(resolved_location) if resolved_location.match?(%r{^https?://})

            schema_path = schema_location_path(resolved_location)
            read_schema_file(schema_path, schema_location)
          end

          private

          def absolute_path?(path)
            # Unix/Linux/macOS: starts with /
            # Windows: starts with drive letter (e.g., C:\)
            path.start_with?("/") || path.match?(%r{^[A-Za-z]:[\\/]})
          end

          def resolve_schema_location(schema_location)
            return schema_location if schema_mappings.empty?

            # Iterate through mappings array
            schema_mappings.each do |mapping|
              from = mapping[:from] || mapping["from"]
              to = mapping[:to] || mapping["to"]
              next unless from && to

              # Check for exact string match
              return to if from.is_a?(String) && from == schema_location

              # Check for regex pattern match
              if from.is_a?(Regexp)
                match = schema_location.match(from)
                if match
                  # Perform regex substitution - return literal result
                  # without platform normalization to preserve cross-platform
                  # path patterns in schema mappings
                  return schema_location.gsub(from, to)
                end
              end
            end

            schema_location
          end

          def schema_location_path(schema_location)
            separator = "/" unless schema_location&.start_with?("/") || location&.end_with?("/")

            location_params = [location, schema_location].compact
            url? ? location_params.join(separator) : File.join(location_params)
          end

          def read_schema_file(schema_path, original_location)
            if url?
              http_get(schema_path)
            else
              unless File.exist?(schema_path)
                raise ::Lutaml::Xml::Schema::Xsd::Error, "Schema file not found: #{schema_path} " \
                                                         "(original location: #{original_location})"
              end
              File.read(schema_path)
            end
          end

          def nullify_location
            @location = nil
            @path = nil
            @url = nil
          end
        end
      end
    end
  end
end
