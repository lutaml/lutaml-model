# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Base class for any renderer that emits a Lutaml::Model::Serializable
      # subclass (the rendered Ruby source for a generated model class).
      #
      # **The full render flow lives here.** A child only overrides the
      # hooks whose value is format-specific. Adding a new generated-class
      # directive is a one-place change in this base / the shared template.
      #
      # Inherited by:
      #   - Lutaml::Model::Schema::XmlCompiler::ComplexType
      #   - Lutaml::Model::Schema::XmlCompiler::Group
      #   - Lutaml::Model::Schema::RngCompiler::GeneratedClass
      class SerializableRenderer
        include ClassBoilerplate

        # The template this renderer evaluates. Hosts can override.
        def template
          Templates::SERIALIZABLE_CLASS
        end

        # ----------------------------------------------------------------
        # Default hook contract — every hook used by
        # Lutaml::Model::Schema::Templates::SERIALIZABLE_CLASS has a
        # sensible default here. Children override only what differs.
        # ----------------------------------------------------------------

        # Required: the CamelCase class name being generated.
        def rendered_class_name
          raise NotImplementedError, "#{self.class} must implement #rendered_class_name"
        end

        # The parent class string. Default: plain Serializable.
        def serializable_class_parent
          "Lutaml::Model::Serializable"
        end

        # `require_relative` / `require` lines emitted under the top-level
        # `require "lutaml/model"`. Empty string when none.
        def serializable_class_required_files
          ""
        end

        # Documentation comment lines emitted above the class declaration.
        def serializable_class_documentation
          ""
        end

        # `attribute :foo, :bar` declaration lines. Empty when none.
        def serializable_class_attributes
          ""
        end

        # `import_model :foo` lines. Empty when none.
        def serializable_class_imports
          ""
        end

        # The root xml directive line inside `xml do ... end`. Typical
        # values:
        #   "element \"FooBar\""    (rooted element model — default)
        #   "type_name \"FooBar\""  (importable type-only model)
        #   nil                     (fragment — emit nothing)
        def xml_root_directive_line
          %(element "#{xml_element_name}")
        end

        # The element name used by the default xml_root_directive_line.
        def xml_element_name
          rendered_class_name
        end

        # The `namespace ClassName` line, or nil to omit.
        def xml_namespace_line
          nil
        end

        # Emit `mixed_content` directive.
        def xml_mixed_content?
          false
        end

        # Emit `map_content to: :content` directive.
        def xml_text_content?
          false
        end

        # The `map_element`/`map_attribute` lines inside the xml block.
        def xml_attribute_mappings
          ""
        end

        # Extra mapping lines emitted after xml_attribute_mappings (used
        # e.g. by XSD ComplexType for simple_content's mapping tail).
        def xml_extra_mappings
          ""
        end
      end
    end
  end
end
