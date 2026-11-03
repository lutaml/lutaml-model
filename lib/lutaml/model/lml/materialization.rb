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
          ids = models.keys.sort
          classes = ids.to_h { |id| [id, allocate(id, models[id])] }
          ids.each { |id| link(id, models[id], classes) }
          classes.freeze
          Materialization.install(classes, models, @namespace) if @namespace
          classes
        end

        # Installs the already built and linked +classes+ under
        # +namespace+, all or nothing, and returns an Installation whose
        # #rollback removes exactly what was installed.
        #
        # Only the first segment of each model name touches the target
        # namespace, and it must be free: an existing constant (module,
        # class or any other value) is a duplicate_id, never descended
        # into. Every deeper segment lands in a holder this install
        # created, parents before children whatever the id sort order
        # ("A::B@default" sorts before "A@default"). All checks run
        # before the first const_set.
        def self.install(classes, models, namespace)
          names = classes.keys.to_h { |id| [id, models.fetch(id)["model"].to_s] }
          check_free(names, namespace)
          installation = Installation.new(namespace)
          holders = {}
          names.sort_by { |id, name| [name.count(":"), id] }.each do |id, name|
            place(name, classes.fetch(id), holders, installation)
          end
          installation
        rescue StandardError
          installation&.rollback
          raise
        end

        def self.check_free(names, namespace)
          seen = {}
          names.each do |id, name|
            if seen.key?(name)
              raise RejectedError.new(:duplicate_id, id, "#{name} is declared by more than one model")
            end

            seen[name] = true
            top = name.split("::").first
            if namespace.const_defined?(top, false)
              raise RejectedError.new(:duplicate_id, id, "#{top} already exists in the target namespace")
            end
          end
        end
        private_class_method :check_free

        def self.place(name, klass, holders, installation)
          *parents, leaf = name.split("::")
          holder = nil
          parents.each_with_index do |part, depth|
            path = parents.first(depth + 1).join("::")
            holders[path] ||= installation.define(holder, part, Module.new)
            holder = holders[path]
          end
          installation.define(holder, leaf, klass)
          holders[name] = klass
        end
        private_class_method :place

        # The constants one install put into the target namespace.
        class Installation
          def initialize(namespace)
            @namespace = namespace
            @names = []
          end

          # const_set +object+ as +name+ under +holder+ (the namespace
          # itself for a top-level name).
          def define(holder, name, object)
            (holder || @namespace).const_set(name, object)
            @names << name unless holder
            object
          end

          def rollback
            @names.each do |name|
              @namespace.send(:remove_const, name) if @namespace.const_defined?(name, false)
            end
            @names = []
          end
        end

        private

        def allocate(id, document)
          klass = Class.new(Lutaml::Model::Serializable)
          name = document["model"].to_s
          unless name.match?(CONST_PATH)
            raise RejectedError.new(:invalid_document, id, "model name #{name.inspect} is not a Ruby constant path")
          end

          klass
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
          options[:default] = default_value(attr) if attr.dig("default", "present")
          options
        end

        def default_value(attr)
          value = attr["default"]["value"]
          float = attr.dig("type", "kind") == "builtin" && attr.dig("type", "name") == "float"
          float ? Float(value) : value
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
