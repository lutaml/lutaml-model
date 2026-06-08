# frozen_string_literal: true

require "tmpdir"
require "uri"

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        extend self

        autoload :SpecBuilder,       "#{__dir__}/xml_compiler/spec_builder"
        autoload :RegistryGenerator, "#{__dir__}/xml_compiler/registry_generator"

        ELEMENT_ORDER_IGNORABLE = %w[import include].freeze

        XML_ADAPTER_NOT_SET_MESSAGE = <<~MSG
          Nokogiri is not set as XML Adapter.
          Make sure Nokogiri is installed and set as XML Adapter eg.
          execute: gem install nokogiri
          require 'lutaml/xml'
          Lutaml::Model::Config.xml_adapter = :nokogiri
        MSG

        XML_DEFINED_ATTRIBUTES = {
          "id" => "Lutaml::Xml::W3c::XmlIdType",
          "lang" => "Lutaml::Xml::W3c::XmlLangType",
          "space" => "Lutaml::Xml::W3c::XmlSpaceType",
          "base" => "Lutaml::Xml::W3c::XmlBaseType",
        }.freeze
        XML_NAMESPACE_URI = "http://www.w3.org/XML/1998/namespace"

        # The SpecBuilder instance set up by `as_models`. Exposed so
        # tests can introspect the walked Definitions::* hashes (e.g.
        # `XmlCompiler.builder.attributes["id"]`) without re-walking.
        attr_reader :builder

        def to_models(schema, options = {})
          as_models(schema, options: options)
          options[:indent] = options[:indent] ? options[:indent].to_i : 2

          unless options.key?(:module_namespace)
            output_dir = options.fetch(:output_dir,
                                       "lutaml_models_#{Time.now.to_i}")
            options[:module_namespace] =
              File.basename(output_dir).split("_").map(&:capitalize).join
          end

          options[:register_id] ||= :default if options[:module_namespace]

          @builder.add_supported_types
          @builder.finalize_required_files!

          # Render eagerly with the user's options so module_namespace=nil
          # produces unwrapped classes. ClassLoader can then force its own
          # namespace for the registry without re-wrapping the classes.
          output = build_output(options, pre_render: true)

          if options[:create_files]
            dir = options.fetch(:output_dir, "lutaml_models_#{Time.now.to_i}")
            FileWriter.write(output, dir, registry_generator: RegistryGenerator)
            true
          else
            ClassLoader.load(output, registry_generator: RegistryGenerator) if options[:load_classes]
            output.sources
          end
        end

        def require_classes(*_args, **_kwargs)
          ClassLoader.load(build_output(module_namespace: "GeneratedModels",
                                        register_id: :default),
                           registry_generator: RegistryGenerator)
        end

        def as_models(schema, options: {})
          unless Config.xml_adapter.name.end_with?("NokogiriAdapter")
            raise Error, XML_ADAPTER_NOT_SET_MESSAGE
          end

          parsed_schema = Lutaml::Xml::Schema::Xsd.parse(
            schema, location: options[:location]
          )
          schemas = Array(parsed_schema)

          @builder = SpecBuilder.new
          @builder.populate_default_attributes
          @builder.collect_namespaces(schemas, options)
          @builder.walk_schemas(schemas)
        end

        private

        def build_output(options, pre_render: false)
          render_opts = {
            module_namespace: options[:module_namespace],
            register_id: options[:register_id] || :default,
            indent: options[:indent] || 2,
          }

          model_entries = @builder.all_models.map do |name, spec|
            payload = pre_render ? render_spec(spec, render_opts) : spec
            CompiledOutput::Entry.new(name, payload, :model)
          end
          namespace_entries = @builder.namespace_classes.map do |name, spec|
            payload = pre_render ? render_spec(spec, render_opts) : spec
            CompiledOutput::Entry.new(name, payload, :namespace)
          end

          CompiledOutput.new(
            entries: model_entries + namespace_entries,
            module_namespace: options[:module_namespace],
            register_id: options[:register_id] || :default,
          )
        end

        def render_spec(spec, opts)
          case spec
          when Definitions::Model          then Renderers::Model.render(spec, **opts)
          when Definitions::RestrictedType then Renderers::RestrictedType.render(spec, **opts)
          when Definitions::UnionType      then Renderers::Union.render(spec, **opts)
          when Definitions::Namespace      then Renderers::Namespace.render(spec, **opts)
          end
        end
      end
    end
  end
end
