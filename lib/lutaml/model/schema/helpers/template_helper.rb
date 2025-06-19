module Lutaml
  module Model
    module Schema
      module Helpers
        module TemplateHelper
          def open_namespaces(namespaces)
            namespaces.map { |ns| "module #{ns}" }.join("\n")
          end

          def close_namespaces(namespaces)
            namespaces.reverse.map { "end" }.join("\n")
          end

          def indent(level)
            "  " * level
          end

          def attribute_line(attribute, level)
            if attribute.choice?
              <<~RUBY.chomp

                #{indent(level)}choice do
                #{attribute.attributes.map { |attr| attribute_line(attr, level + 1) }.join("\n")}
                #{indent(level)}end
              RUBY
            else
              "#{indent(level)}attribute #{attribute_properties(attribute)}"
            end
          end

          def attribute_properties(attribute)
            # properties = {}
            # properties[:default] = attribute.default if attribute.default
            # properties[:collection] = true if attribute.collection?

            required_properties = ":#{attribute.name}, #{attribute.type}"
            required_properties += ", default: #{attribute.default.inspect}" if attribute.default
            required_properties += ", collection: #{attribute.collection}" if attribute.collection?
            required_properties += ", values: #{attribute.options[:enum].inspect}" if attribute.options[:enum]
            required_properties += ", pattern: #{attribute.options[:pattern].inspect}" if attribute.options[:pattern]

            required_properties
          end
        end
      end
    end
  end
end
