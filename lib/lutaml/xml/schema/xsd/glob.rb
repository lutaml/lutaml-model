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
            @schema_path = SchemaPath.new(location,
                                          schema_mappings: @schema_mappings)
          end

          def path_or_url(location)
            return nullify_location if location.nil?

            @schema_path = SchemaPath.new(location,
                                          schema_mappings: schema_mappings)
            @location = location
            @url = @schema_path.url&.to_s
            @path = @schema_path.path
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

            schema_path.include_schema(schema_location)
          end

          def location_for(schema_location)
            return unless location? && schema_location

            schema_path.location_for(schema_location)
          end

          def schema_location_path(schema_location)
            schema_path.schema_location_path(schema_location)
          end

          def resolve_schema_location(schema_location)
            schema_path.resolve_schema_location(schema_location)
          end

          def with_location(location)
            snapshot = {
              location: @location,
              path: @path,
              url: @url,
              schema_path: @schema_path,
            }
            path_or_url(location)
            yield
          ensure
            @location = snapshot[:location]
            @path = snapshot[:path]
            @url = snapshot[:url]
            @schema_path = snapshot[:schema_path]
          end

          private

          def schema_path
            @schema_path ||= SchemaPath.new(location,
                                            schema_mappings: schema_mappings)
          end

          def nullify_location
            @location = nil
            @path = nil
            @url = nil
            @schema_path = nil
          end
        end
      end
    end
  end
end
