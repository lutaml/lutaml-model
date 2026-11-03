# frozen_string_literal: true

require "lutaml/model"
require_relative "rejected_error"

module Lutaml
  module Model
    module Lml
      # Allocates and links a fresh Ruby declaration graph from a
      # validated neutral LML bundle (lutaml-model#1033, card 03a).
      #
      # Two passes make nested and cyclic models work without the source
      # constants: every model id first gets an empty Serializable class
      # (allocate), then attributes are declared against those class
      # objects (link). Types resolve only through the bundle itself, the
      # builtin registry, or the trusted +type_bindings+ map supplied by
      # the caller; nothing is evaluated or required from the document and
      # no global constant lookup is used.
      #
      # Mappings (xml/json/yaml) belong to MappingCompiler.apply.
      class Materialization
        ATTRIBUTE_KEYS = %w[name type required collection default
                            initialize_empty values].freeze
        CONST_PATH = /\A[A-Z]\w*(::[A-Z]\w*)*\z/

        # @param bundle [Hash] a validated bundle (string keys)
        # @param namespace [Module, nil] holder for the generated
        #   constants; nil leaves the classes anonymous
        # @param type_bindings [Hash{String=>Class}] trusted classes by
        #   value-type id (and custom collection class name)
        # @return [Hash{String=>Class}] model id => generated class
        def self.build(bundle, namespace: nil, type_bindings: {})
          new(bundle, namespace: namespace, type_bindings: type_bindings).build
        end

        def initialize(bundle, namespace:, type_bindings:)
          @bundle = bundle
          @namespace = namespace
          @bindings = type_bindings || {}
        end

        def build
          models = @bundle["models"] || {}
          classes = models.keys.sort.to_h { |id| [id, allocate(id, models[id])] }
          models.keys.sort.each { |id| link(id, models[id], classes) }
          classes.freeze
        end

        private

        def allocate(id, document)
          klass = Class.new(Lutaml::Model::Serializable)
          name = document["model"].to_s
          unless name.match?(CONST_PATH)
            raise RejectedError.new(:invalid_document, id, "model name #{name.inspect} is not a Ruby constant path")
          end

          install(id, name, klass) if @namespace
          klass
        end

        def install(id, name, klass)
          *parents, leaf = name.split("::")
          holder = parents.reduce(@namespace) do |mod, part|
            if mod.const_defined?(part, false)
              mod.const_get(part, false)
            else
              mod.const_set(part, Module.new)
            end
          end
          if holder.const_defined?(leaf, false)
            raise RejectedError.new(:duplicate_id, id, "#{name} already exists in the target namespace")
          end

          holder.const_set(leaf, klass)
        end

        def link(id, document, classes)
          document["attributes"].to_a.each do |attr|
            declare(id, classes[id], attr, classes)
          end
        end

        def declare(id, klass, attr, classes)
          extra = attr.keys - ATTRIBUTE_KEYS
          unless extra.empty?
            raise RejectedError.new(:invalid_document, id,
                                    "attribute #{attr['name']}: unhandled key(s) #{extra.sort.join(', ')}")
          end

          type = resolve_type(id, attr, classes)
          options = attribute_options(id, attr)
          klass.attribute(attr["name"].to_sym, type, **options)
        end

        def attribute_options(id, attr)
          options = {}
          options[:required] = true if attr["required"]
          options[:initialize_empty] = true if attr["initialize_empty"]
          options[:values] = attr["values"].to_a if attr["values"]
          options[:collection] = collection_option(id, attr["collection"]) if attr["collection"]
          options[:default] = attr["default"]["value"] if attr.dig("default", "present")
          options
        end

        def collection_option(id, spec)
          return true if spec == true

          min = spec["min"] || 0
          max = spec["max"]
          return min..(max || Float::INFINITY) unless spec["class"]

          unless min.zero? && max.nil?
            raise RejectedError.new(:unsupported_mapping, id,
                                    "a custom collection class cannot carry a min/max range")
          end

          binding_for(id, spec["class"])
        end

        def resolve_type(id, attr, classes)
          type = attr["type"]
          case type["kind"]
          when "builtin" then builtin(id, type["name"])
          when "model"
            classes.fetch(type["id"]) do
              raise RejectedError.new(:dangling_reference, id, "attribute #{attr['name']} -> #{type['id']}")
            end
          when "value" then binding_for(id, type["id"])
          else raise RejectedError.new(:unknown_type, id, "attribute #{attr['name']}: kind #{type['kind'].inspect}")
          end
        end

        def builtin(id, name)
          return name.to_sym if builtin_names.include?(name.to_s)

          raise RejectedError.new(:unknown_type, id, "unknown builtin #{name.inspect}")
        end

        def builtin_names
          @builtin_names ||= begin
            registry = TypeRegistry.new
            Type.register_builtin_types_in(registry)
            registry.types.keys.map(&:to_s)
          end
        end

        def binding_for(id, key)
          @bindings.fetch(key) do
            raise RejectedError.new(:missing_type_binding, id, "no trusted binding for #{key}")
          end
        end
      end
    end
  end
end
