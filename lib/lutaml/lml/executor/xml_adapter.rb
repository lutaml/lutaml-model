# frozen_string_literal: true

require "moxml"

module Lutaml
  module Lml
    class Executor
      # XML format adapter. Reads XML files and maps elements to hydrated
      # compiled-class instances, and writes instances back to XML.
      #
      # Registered for format "xml" via FormatAdapter::BUILTIN_ADAPTERS.
      #
      # Element-to-attribute mapping is provided by the lutaml-model XML
      # mapping generated on each compiled class by ModelCompiler. This
      # adapter only selects which XML elements correspond to records
      # (via the `where` XPath from the import definition) and hands
      # each one to `target_class.from_xml` for deserialization.
      #
      # Import shape (from LML `import { xml "..." { map_to X; where "/y" } }`):
      #   - imp.file             = path to XML file
      #   - imp.attributes       = TopElementAttribute list including:
      #       map_to: TargetClass (compiled-class key)
      #       where:  XPath selector for each record element
      #
      # Export shape (from LML `export { format xml { file "..."; root "X" } }`):
      #   - exp.attributes       = TopElementAttribute list including:
      #       file:      output path
      #       root:      root tag name (defaults to compiled class name)
      #       indent:    "true" / "false" (default true)
      #       encoding:  encoding string (default UTF-8)
      class XmlAdapter
        extend AdapterHelpers

        DEFAULT_ENCODING = "UTF-8"
        DEFAULT_SELECTOR = "/*/*"
        DEFAULT_ROOT_SUFFIX = "s"

        class << self
          # Read an XML file and map elements to compiled-class instances.
          # Returns an array of hydrated objects.
          def import(imp, compiled:)
            return [] unless imp.file
            return [] unless imp.attributes&.any?

            target_class = resolve_target_class(imp.attributes, compiled)
            return [] unless target_class

            path = imp.file
            return [] unless File.exist?(path)

            doc = Moxml.parse(File.read(path))
            selector = attribute_value(imp.attributes, "where") || DEFAULT_SELECTOR

            doc.xpath(selector).map do |element|
              target_class.from_xml(element.to_xml)
            end
          end

          # Write instances to an XML file.
          def export(exp, instances, compiled:)
            return if instances.empty?

            path = attribute_value(exp.attributes, "file")
            return unless path && !path.empty?

            class_name, target_class = find_class_for_instance(instances.first, compiled)
            return unless target_class

            options = export_options(exp, class_name)
            File.write(path, build_export_xml(instances, options))
          end

          private

          def export_options(exp, class_name)
            {
              root: attribute_value(exp.attributes, "root") || "#{class_name}#{DEFAULT_ROOT_SUFFIX}",
              indent: attribute_value(exp.attributes, "indent") != "false",
              encoding: attribute_value(exp.attributes, "encoding") || DEFAULT_ENCODING
            }
          end

          # Builds the export XML by parsing each instance's `to_xml`
          # output, then grafting its root element under a single
          # configurable root. lutaml-model handles per-record
          # serialization via the generated XML mapping.
          def build_export_xml(instances, options)
            doc = Moxml.parse("<#{options[:root]}/>")
            root = doc.root

            instances.each do |inst|
              record_doc = Moxml.parse(inst.to_xml)
              root.add_child(record_doc.root)
            end

            doc.to_xml(indent: options[:indent] ? 2 : 0)
          end
        end
      end
    end
  end
end
