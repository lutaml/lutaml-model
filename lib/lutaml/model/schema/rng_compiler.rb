# frozen_string_literal: true

require "uri"

module Lutaml
  module Model
    module Schema
      # Compiles a parsed RNG grammar into Lutaml::Model::Serializable Ruby
      # source. Mirrors XmlCompiler in API, options, and output format.
      #
      # Requires the `rng` gem (https://github.com/lutaml/rng) at runtime --
      # that gem provides the Rng::Grammar parsing model. lutaml-model itself
      # has no dependency on it. Registration of Schema.from_relaxng is done
      # in lib/lutaml/xml.rb (alongside Schema.from_xml and Schema.to_relaxng).
      #
      # Entry point: Lutaml::Model::Schema::RngCompiler.to_models(rng, options)
      module RngCompiler
        extend self

        autoload :MemberCollector,   "#{__dir__}/rng_compiler/member_collector"
        autoload :ElementVisitor,    "#{__dir__}/rng_compiler/element_visitor"
        autoload :DefineClassifier,  "#{__dir__}/rng_compiler/define_classifier"
        autoload :ValueTypeResolver, "#{__dir__}/rng_compiler/value_type_resolver"
        autoload :RngHelpers,        "#{__dir__}/rng_compiler/rng_helpers"

        # Map RNG <data type="..."/> values to Lutaml::Model attribute type
        # symbols. Mirrors Lutaml::Xml::Schema::RelaxngSchema.get_relaxng_type
        # so RNG-generate + compile-back is a round-trip.
        DATA_TYPE_MAP = {
          "string" => :string,
          "integer" => :integer,
          "int" => :integer,
          "long" => :integer,
          "boolean" => :boolean,
          "float" => :float,
          "double" => :float,
          "decimal" => :decimal,
          "date" => :date,
          "dateTime" => :date_time,
          "time" => :time,
        }.freeze

        DEFAULT_DATA_TYPE = :string

        def to_models(rng, options = {})
          require_rng_parser!

          opts = normalize_options(options)
          output = compile(rng, opts)

          dispatch_output(output, normalize_options(opts))
        end

        def compile(rng, options = {})
          require_rng_parser!

          opts = normalize_options(options)
          grammar = parse_grammar(rng, opts)
          classes, namespaces = compile_grammar(grammar)

          entries =
            classes.map { |name, spec| CompiledOutput::Entry.new(name, spec, :model) } +
            namespaces.map { |name, spec| CompiledOutput::Entry.new(name, spec, :namespace) }

          CompiledOutput.new(
            entries: entries,
            module_namespace: opts[:module_namespace],
            register_id: opts[:register_id],
          )
        end

        private

        def require_rng_parser!
          return if defined?(::Rng::Grammar)

          raise "RNG schema compilation requires the rng gem. " \
                "Add `gem \"rng\"` to your Gemfile."
        end

        def normalize_options(options)
          opts = options.dup
          opts[:indent]      ||= 2
          opts[:register_id] ||= :default
          opts
        end

        def parse_grammar(rng, options)
          return rng if rng.is_a?(::Rng::Grammar)

          if options[:location]
            ::Rng.parse(rng, location: options[:location], resolve_external: true)
          else
            ::Rng::Grammar.from_xml(rng)
          end
        end

        def dispatch_output(output, options)
          if options[:create_files]
            dir = options.fetch(
              :output_dir,
              options.fetch(:default_output_dir, "rng_models_#{Time.now.to_i}"),
            )
            FileWriter.write(output, dir)
            true
          elsif options[:load_classes]
            ClassLoader.load(output)
            output.sources
          else
            output.sources
          end
        end

        # Returns [classes_hash, namespaces_hash]. `classes` holds
        # Definitions::Model / Definitions::RestrictedType / Definitions::UnionType.
        # `namespaces` holds Definitions::Namespace.
        def compile_grammar(grammar)
          defines = grammar.define.to_h { |d| [d.name, d] }
          classes = {}
          namespaces = {}
          registrar = ->(uri) { register_namespace(namespaces, uri) }

          default_uri = grammar_default_ns(grammar)
          visitor = ElementVisitor.new(
            defines, classes,
            default_namespace_class: default_uri && registrar.call(default_uri),
            register_namespace: registrar
          )

          grammar.start.each do |start|
            visitor.compile_element(start.element) if start.element
            Array(start.ref).each do |ref|
              target = defines[ref.name]
              visitor.compile_define(target) if target
            end
          end

          # Sweep: compile any <define> not reachable from <start>.
          grammar.define.each { |define| visitor.compile_define(define) }

          finalize_models(classes)

          [classes, namespaces]
        end

        def grammar_default_ns(grammar)
          uri = grammar.respond_to?(:ns) ? grammar.ns : nil
          uri if uri.is_a?(String) && !uri.empty?
        end

        # Build-or-find the namespace for `uri`; returns its class_name.
        # RNG/RNC name-prefixed elements are namespace-qualified, so descendant
        # elements inherit the namespace via element_form_default :qualified.
        def register_namespace(namespaces, uri)
          existing = namespaces.values.find { |ns| ns.uri == uri }
          return existing.class_name if existing

          # Distinct URIs can map to the same generated class name AND prefix
          # (e.g. both `urn:a` and `urn:b` -> "DefaultNamespace"/"ns"); uniquify
          # both so one namespace does not silently overwrite the other or
          # collide with its prefix at serialization.
          class_name = RngHelpers.unique_class_name(
            namespaces, NamespaceNaming.class_name_for(uri)
          )
          ns = Definitions::Namespace.new(
            class_name: class_name,
            uri: uri,
            prefix_default: unique_prefix(namespaces, NamespaceNaming.prefix_for(uri)),
            element_form_default: :qualified,
          )
          namespaces[class_name] = ns
          class_name
        end

        # A prefix that does not collide with an already-registered namespace's
        # prefix (appends 2, 3, ... on collision).
        def unique_prefix(namespaces, base)
          taken = namespaces.values.map(&:prefix_default)
          return base unless taken.include?(base)

          counter = 2
          counter += 1 while taken.include?("#{base}#{counter}")
          "#{base}#{counter}"
        end

        # Set `required_files` so each generated file requires its
        # dependencies: a Model requires its imports/class_ref types/namespace;
        # a namespaced RestrictedType requires its namespace class.
        def finalize_models(classes)
          classes.each_value do |spec|
            case spec
            when Definitions::Model
              spec.required_files =
                Renderers::RequiredFilesCalculator.class_names_for_rng(spec)
                  .map { |dep| require_relative_line(dep) }
            when Definitions::RestrictedType
              next unless spec.namespace_class_name

              spec.required_files = namespaced_type_requires(spec)
            end
          end
        end

        # A namespaced RestrictedType requires its namespace class and, when it
        # subclasses another generated type (a bare name, not a Lutaml built-in),
        # that parent too.
        def namespaced_type_requires(spec)
          deps = [spec.namespace_class_name]
          parent = spec.parent_class
          deps << parent if parent && !parent.include?("::")
          deps.map { |dep| require_relative_line(dep) }
        end

        def require_relative_line(class_name)
          %(require_relative "#{Utils.snake_case(class_name)}")
        end
      end
    end
  end
end
