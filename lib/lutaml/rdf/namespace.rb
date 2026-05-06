# frozen_string_literal: true

module Lutaml
  module Rdf
    class Namespace
      class << self
        def uri(value = nil)
          return @uri if value.nil?
          if @uri
            raise FrozenError,
                  "#{name}.uri is already set to #{@uri.inspect}"
          end

          @uri = value.freeze
        end

        def prefix(value = nil)
          return @prefix if value.nil?
          if @prefix
            raise FrozenError,
                  "#{name}.prefix is already set to #{@prefix.inspect}"
          end

          @prefix = value.to_s.freeze
        end

        def [](local_name)
          "#{uri}#{local_name}"
        end

        def prefixed(local_name)
          "#{prefix}:#{local_name}"
        end

        def resolve_compact_iri(compact_iri, namespaces)
          return compact_iri unless compact_iri.include?(":")

          pfx, local = compact_iri.split(":", 2)
          ns = namespaces.find { |n| n.prefix == pfx }
          ns ? ns[local] : compact_iri
        end

        def ==(other)
          other.is_a?(Class) && other < Namespace &&
            other.uri == uri && other.prefix == prefix
        end

        def hash
          [uri, prefix].hash
        end

        def to_s
          "#{name}(prefix: #{prefix.inspect}, uri: #{uri.inspect})"
        end
      end
    end
  end
end
