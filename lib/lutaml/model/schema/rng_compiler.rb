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

          namespace = build_grammar_namespace(grammar, namespaces)
          visitor = ElementVisitor.new(
            defines, classes, namespace_class: namespace&.class_name
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

        def build_grammar_namespace(grammar, namespaces)
          uri = grammar.respond_to?(:ns) ? grammar.ns : nil
          return nil if Lutaml::Model::Utils.blank?(uri)
          return nil unless uri.is_a?(String)

          ns = Definitions::Namespace.new(
            class_name: NamespaceNaming.class_name_for(uri),
            uri: uri,
            prefix_default: NamespaceNaming.prefix_for(uri),
          )
          namespaces[ns.class_name] = ns
          ns
        end

        # Set `required_files` on every Definitions::Model from the deps it
        # picked up during walking (imports, class_ref attributes, namespace).
        def finalize_models(classes)
          classes.each_value do |spec|
            next unless spec.is_a?(Definitions::Model)

            spec.required_files = Renderers::RequiredFilesCalculator
              .class_names_for_rng(spec)
              .map { |dep| %(require_relative "#{Utils.snake_case(dep)}") }
          end
        end
      end
    end
  end
end
