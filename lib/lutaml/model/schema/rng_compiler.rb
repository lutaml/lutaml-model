# frozen_string_literal: true

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

        autoload :ClassBoilerplate,  "#{__dir__}/rng_compiler/class_boilerplate"
        autoload :MemberCollector,   "#{__dir__}/rng_compiler/member_collector"
        autoload :GeneratedClass,    "#{__dir__}/rng_compiler/generated_class"
        autoload :ElementVisitor,    "#{__dir__}/rng_compiler/element_visitor"
        autoload :DefineClassifier,  "#{__dir__}/rng_compiler/define_classifier"
        autoload :ValueTypeResolver, "#{__dir__}/rng_compiler/value_type_resolver"
        autoload :Attribute,         "#{__dir__}/rng_compiler/attribute"
        autoload :Choice,            "#{__dir__}/rng_compiler/choice"
        autoload :Sequence,          "#{__dir__}/rng_compiler/sequence"
        autoload :Restriction,       "#{__dir__}/rng_compiler/restriction"
        autoload :SimpleType,        "#{__dir__}/rng_compiler/simple_type"
        autoload :UnionType,         "#{__dir__}/rng_compiler/union_type"
        autoload :Namespace,         "#{__dir__}/rng_compiler/namespace"
        autoload :Utils,             "#{__dir__}/rng_compiler/utils"
        autoload :RegistryGenerator, "#{__dir__}/rng_compiler/registry_generator"
        autoload :CompiledOutput,    "#{__dir__}/rng_compiler/compiled_output"
        autoload :FileWriter,        "#{__dir__}/rng_compiler/file_writer"
        autoload :ClassLoader,       "#{__dir__}/rng_compiler/class_loader"

        # Map RNG <data type="..."/> values to Lutaml::Model attribute type
        # symbols. Mirrors Lutaml::Xml::Schema::RelaxngSchema.get_relaxng_type
        # so RNG-generate + compile-back is a round-trip.
        DATA_TYPE_MAP = {
          "string"   => :string,
          "integer"  => :integer,
          "int"      => :integer,
          "long"     => :integer,
          "boolean"  => :boolean,
          "float"    => :float,
          "double"   => :float,
          "decimal"  => :decimal,
          "date"     => :date,
          "dateTime" => :date_time,
          "time"     => :time,
        }.freeze

        DEFAULT_DATA_TYPE = :string

        # Public entry point. Compiles the RNG, then dispatches based on
        # options:
        #   :create_files -> write files to :output_dir (returns true)
        #   :load_classes -> write to tmpdir and require (returns sources)
        #   otherwise     -> return the sources hash
        def to_models(rng, options = {})
          require_rng_parser!

          opts = normalize_options(options)
          output = compile(rng, opts)

          dispatch_output(output, opts)
        end

        # Pure compilation: RNG (string or Rng::Grammar) -> CompiledOutput.
        # No I/O. Useful in its own right and the building block of to_models.
        def compile(rng, options = {})
          require_rng_parser!

          opts = normalize_options(options)
          grammar = parse_grammar(rng, opts)
          classes = compile_grammar(grammar)
          sources = render_sources(classes, opts)

          CompiledOutput.new(
            classes: classes,
            sources: sources,
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
            # Resolve <include>/<externalRef>/<parentRef> against the
            # schema's location (mirrors XSD compiler's `:location` option).
            ::Rng.parse(rng, location: options[:location], resolve_external: true)
          else
            ::Rng::Grammar.from_xml(rng)
          end
        end

        def dispatch_output(output, options)
          if options[:create_files]
            dir = options.fetch(:output_dir, "rng_models_#{Time.now.to_i}")
            FileWriter.write(output, dir)
            true
          elsif options[:load_classes]
            ClassLoader.load(output)
            output.sources
          else
            output.sources
          end
        end

        def compile_grammar(grammar)
          defines = grammar.define.to_h { |d| [d.name, d] }
          classes = {}

          namespace = build_grammar_namespace(grammar, classes)
          visitor = ElementVisitor.new(
            defines, classes, namespace_class: namespace&.class_name,
          )

          grammar.start.each do |start|
            visitor.compile_element(start.element) if start.element

            # <start> may contain a single <ref> rather than a collection.
            Array(start.ref).each do |ref|
              target = defines[ref.name]
              visitor.compile_define(target) if target
            end
          end

          grammar.define.each { |define| visitor.compile_define(define) }

          classes
        end

        # Build a Namespace from <grammar ns="..."> and register it in
        # `classes`. Returns the namespace, or nil if no `ns` is set.
        def build_grammar_namespace(grammar, classes)
          uri = grammar.respond_to?(:ns) ? grammar.ns : nil
          return nil if Lutaml::Model::Utils.blank?(uri)
          return nil unless uri.is_a?(String)

          ns = Namespace.new(uri: uri)
          classes[ns.class_name] = ns
          ns
        end

        def render_sources(classes, options)
          classes.transform_values do |gen|
            gen.render(
              indent: options[:indent],
              module_namespace: options[:module_namespace],
              register_id: options[:register_id],
            )
          end
        end
      end
    end
  end
end
