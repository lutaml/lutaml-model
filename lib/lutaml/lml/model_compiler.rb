# frozen_string_literal: true

require 'json'

module Lutaml
  module Lml
    # Compiles LML model definitions into anonymous
    # Lutaml::Model::Serializable subclasses, hydrates instance data
    # against them, and applies declared serialization mappings. The
    # concern modules (Hydration, Validation, Enums,
    # SerializationMappings, StringFormats) share this class's state.
    class ModelCompiler
      autoload :Hydration, "lutaml/lml/model_compiler/hydration"
      autoload :Validation, "lutaml/lml/model_compiler/validation"
      autoload :Enums, "lutaml/lml/model_compiler/enums"
      autoload :SerializationMappings, "lutaml/lml/model_compiler/serialization_mappings"
      autoload :StringFormats, "lutaml/lml/model_compiler/string_formats"

      class ValidationError < Error; end

      # The default generated namespace nests under Lutaml::Lml so
      # compiled constants never collide with top-level constants.
      DEFAULT_NAMESPACE = 'Lutaml::Lml::Generated'

      TYPE_MAP = {
        'String' => :string,
        'string' => :string,
        'Integer' => :integer,
        'integer' => :integer,
        'Boolean' => :boolean,
        'boolean' => :boolean,
        'Float' => :float,
        'float' => :float,
        'Date' => :date,
        'date_time' => :date_time,
        'DateTime' => :date_time,
        'Time' => :time,
        'Uri' => :string,
      }.freeze

      # Tokens that denote unbounded cardinality in LML attribute
      # declarations. Anything else must parse as an Integer.
      UNBOUNDED_TOKENS = %w[* n N unbounded].freeze

      include Hydration
      include Validation
      include Enums
      include SerializationMappings
      include StringFormats

      def initialize(namespace: nil, artifact_paths: {}, default_artifact: nil)
        @namespace = namespace
        @artifact_paths = artifact_paths
        @default_artifact = default_artifact
        @compiled = {}
        @forward_refs = {}
        @enum_names = Set.new
        @enum_classes = {}
        @declared_namespaces = []
        @serialization_mappings = []
        @namespace_classes = {}
        @class_defs = {}
      end

      def compile(input)
        doc = Lutaml::Lml.parse_document(input)
        compile_document(doc)
        @compiled
      end

      def hydrate(input)
        doc = input.is_a?(Document) ? input : Lutaml::Lml.parse_document(input)
        compile_document(doc) unless @compiled.any?
        return {} unless doc.instance

        hydrate_instance(doc.instance)
      rescue Lutaml::Lml::Error
        raise
      rescue StandardError => e
        raise HydrationError.new(
          "hydration failed: #{e.message}",
          diagnostic: Diagnostic.build(
            'hydration/LML-H01',
            message: e.message,
            file: input.is_a?(Document) ? input.source_path : nil,
          ),
        )
      end

      def compiled_classes
        @compiled
      end

      # Validate an instances document against compiled models.
      #
      # Accepts the instances input as a String, IO, StringIO, or a
      # pre-parsed Document. If +compiled:+ is supplied, that registry is
      # used; otherwise models are compiled from the same input (which
      # must therefore contain a models section).
      #
      # Returns an array of validation error strings (empty if all pass).
      def validate(input, compiled: nil)
        doc = input.is_a?(Document) ? input : Lutaml::Lml.parse_document(input)
        if compiled
          @compiled = compiled
        else
          compile_document(doc)
        end

        errors = []
        validate_instance(doc.instance, errors) if doc.instance
        errors
      end

      private

      def compile_document(doc)
        @declared_namespaces = Array(doc.namespaces)
        @serialization_mappings = Array(doc.serialization_mappings)
        doc.classes.each { |c| compile_class(c) }
        hoist_class_serialization_mappings(doc)
        doc.enums.each { |e| compile_enum(e) }
        doc.data_types.each { |dt| compile_data_type(dt) }
        resolve_forward_references
        apply_xml_mappings
        apply_key_value_mappings
        register_string_formats(doc)
      end

      def resolve_forward_references
        @forward_refs.each do |class_name, deferred_attrs|
          klass = @compiled[class_name]
          next unless klass

          deferred_attrs.each do |attr_name, raw_type, _type, options|
            resolved = resolve_type(raw_type)
            klass.attribute attr_name, resolved, **options
          end
        end
      end

      def compile_class(klass_def)
        name = klass_def.name.to_s
        @class_defs[name] = klass_def
        compiled_klass = build_compiled_class(klass_def)
        apply_declared_mappings(compiled_klass, klass_def)
        declare_derived_fields(compiled_klass, klass_def)
        register(name, compiled_klass)
      end

      alias compile_data_type compile_class
      def build_compiled_class(def_obj)
        all_attrs = build_attributes(def_obj)
        immediate, deferred = all_attrs.partition do |(_, raw_type, type, _)|
          type != :string || TYPE_MAP.key?(raw_type) || raw_type.start_with?('reference:(')
        end

        compiled_klass = Class.new(Lutaml::Model::Serializable) do
          immediate.each do |attr_name, _raw, type, options|
            attribute attr_name, type, options
          end
        end
        render_nil_map = Array(def_obj.attributes).to_h do |a|
          [a.name.to_sym, declared_render_nil(a)]
        end.compact
        unless render_nil_map.empty?
          compiled_klass.class_eval do
            @lml_render_nil = render_nil_map

            class << self
              attr_reader :lml_render_nil
            end
          end
          apply_render_nil_mappings(compiled_klass, render_nil_map)
        end

        name = def_obj.name.to_s
        @forward_refs[name] = deferred unless deferred.empty?
        compiled_klass
      end

      def build_attributes(klass_def)
        Array(klass_def.attributes).map do |attr|
          attr_name = attr.name.to_sym
          raw_type = resolve_values_type(klass_def, attr)
          type = resolve_type(raw_type)
          options = build_options(attr)
          [attr_name, raw_type, type, options]
        end
      end

      def resolve_type(type_name)
        return TYPE_MAP[type_name] if TYPE_MAP.key?(type_name)
        return :string if type_name.start_with?('reference:(')
        return @compiled[type_name] if @compiled.key?(type_name)

        :string
      end

      def build_options(attr)
        declared = declared_attribute_options(attr)
        options = {}
        card = attr.cardinality
        unless card
          # LML attributes without an explicit cardinality are optional (0..1)
          options[:default] = declared[:default]
          return options
        end

        min = parse_cardinality_value(card.min)
        max = parse_cardinality_value(card.max)

        collection = (max && (max > 1 || max == Float::INFINITY)) ||
                     (max.nil? && min && min > 1)
        if collection
          options[:collection] = true
        elsif min.zero?
          options[:default] = nil
        end
        # a declared default literal wins over the absent-marker
        options[:default] = declared[:default] if declared.key?(:default)
        options
      end

      # L7b: default <literal> and render_nil true|false ride the
      # keyword-attribute properties (bare name-value lines). Defaults
      # fire only on ABSENT input; render_nil mirrors lutaml-model.
      def declared_attribute_options(attr)
        options = {}
        Array(attr.properties).each do |prop|
          next unless prop.name.to_s == 'default'

          value = prop.value
          value = value[:string] if value.is_a?(Hash) && value.key?(:string)
          options[:default] = value&.to_s
        end
        options
      end

      # render_nil is a lutaml-model MAPPING option, not an attribute
      # option: collect the declaration for the mapping passes
      def declared_render_nil(attr)
        prop = Array(attr.properties).find { |prop| prop.name.to_s == 'render_nil' }
        prop ? prop.value.to_s == 'true' : nil
      end

      def parse_cardinality_value(val)
        return nil if val.nil?
        return Float::INFINITY if UNBOUNDED_TOKENS.include?(val.to_s)
        return val.to_i if val.to_s.match?(/\A\d+\z/)

        message = "Unrecognized cardinality token: #{val.inspect}"
        raise ValidationError.new(
          message,
          diagnostic: Diagnostic.build('contract/LML-C04', message: message),
        )
      end

      def declare_derived_fields(compiled_klass, def_obj)
        return unless def_obj.is_a?(UmlClass) || def_obj.is_a?(DataType)

        derived = Array(def_obj.derived_fields)
        return if derived.empty?

        compiled_klass.class_eval do
          @lml_derived_fields = derived.map(&:name).map(&:to_sym)
          def self.derived_fields
            @lml_derived_fields
          end
        end
        derived.each do |field|
          compiled_klass.attribute field.name.to_sym, resolve_type(field.type.to_s)
        end
      end

      def artifact_path_for(reference)
        mapped = @artifact_paths && @artifact_paths[reference]
        return mapped if mapped && File.exist?(mapped.to_s)
        return reference if File.exist?(reference)

        nil
      end

      # Emit KV mappings carrying render_nil for the declared
      # attributes (yaml/json round-trips honor them)
      def apply_render_nil_mappings(compiled_klass, render_nil_map)
        %i[yaml json].each do |fmt|
          compiled_klass.public_send(fmt) do |mapping|
            render_nil_map.each do |name, flag|
              mapping.map name.to_s, to: name, render_nil: flag
            end
          end
        end
      end

      def register(name, klass)
        @compiled[name] = klass
        return name_anonymous_class(klass, name) unless @namespace

        namespace_module.const_set(name, klass)
      end

      # Without a target namespace the class stays anonymous, and
      # lutaml-model's schema generators need a class name for $defs/$ref.
      def name_anonymous_class(klass, name)
        klass.define_singleton_method(:name) { name }
      end

      def namespace_module
        return @namespace if @namespace.is_a?(Module)

        @namespace_module ||= begin
          chain = @namespace.to_s.split('::')
          chain.reduce(Object) do |parent, name|
            parent.const_get(name)
          rescue NameError
            parent.const_set(name, Module.new)
          end
        end
      end
    end
  end
end
