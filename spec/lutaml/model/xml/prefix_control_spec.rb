require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"

# Tests for Solution 1: Prefix Control Feature
# These tests validate the prefix control functionality described in PROPOSAL-default-namespace.md
# Status: Feature implementation in progress
RSpec.describe "XML Prefix Control" do
  # Define test namespace
  let(:app_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
      prefix_default "app"
      element_form_default :qualified
    end
  end

  shared_examples "prefix control behavior" do |adapter_class|
    before do
      Lutaml::Model::Config.xml_adapter = adapter_class
    end

    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "with namespaced model attribute" do
      # Rationale: When using a namespaced attribute type, and the namespace is
      # the same as the parent model, we expect the attribute to be serialized
      # with the same prefix/default namespace.

      let(:template_string_class) do
        ns = app_namespace
        Class.new(Lutaml::Model::Type::String) do
          xml_namespace ns

          def self.name
            "TemplateString"
          end
        end
      end

      # Define test model
      let(:properties_class) do
        ns = app_namespace
        ts = template_string_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :template, ts

          xml do
            element "Properties"
            namespace ns
            map_element "Template", to: :template
          end

          def self.name
            "Properties"
          end
        end
      end

      let(:instance) { properties_class.new(template: "Normal.dotm") }

      describe "default behavior (no prefix option)" do
        # Target behavior: Should use default namespace (no prefix)
        # Current behavior: Uses prefix (app:) with both xmlns and xmlns:app
        it "uses default namespace (xmlns='...')" do
          xml = instance.to_xml

          # Should have only xmlns, no xmlns:app
          expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<Template>Normal.dotm</Template>")
          expect(xml).not_to include("app:")
          expect(xml).not_to include("xmlns:app=")
        end
      end

      describe "prefix: true" do
        # Using prefix includes both default and prefixed xmlns (valid but redundant per W3C)
        it "uses defined prefix_default" do
          xml = instance.to_xml(prefix: true)

          # Should have xmlns:app and use the prefix
          expect(xml).to include('<app:Properties xmlns:app="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<app:Template>Normal.dotm</app:Template>")
        end
      end

      describe "prefix: 'custom'" do
        # Custom prefix support not yet implemented - uses default prefix_default instead
        it "uses custom prefix string" do
          xml = instance.to_xml(prefix: "custom")

          expect(xml).to include('<custom:Properties xmlns:custom="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<custom:Template>Normal.dotm</custom:Template>")
          # Should not have redundant declarations
          expect(xml).not_to match(/xmlns="/)
          expect(xml).not_to match(/xmlns:app=/)
        end
      end

      describe "prefix: false" do
        # Target behavior: Should use default namespace explicitly
        # Current behavior: Uses default namespace but still declares xmlns:app
        it "explicitly uses default namespace" do
          xml = instance.to_xml(prefix: false)

          expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<Template>Normal.dotm</Template>")
          expect(xml).not_to include("app:")
          # Should not have redundant xmlns:app
          expect(xml).not_to include("xmlns:app=")
        end
      end

      describe "prefix: nil" do
        # Target behavior: Should use default namespace (same as prefix: false)
        # Current behavior: Uses default namespace but still declares xmlns:app
        it "explicitly uses default namespace" do
          xml = instance.to_xml(prefix: nil)

          expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<Template>Normal.dotm</Template>")
          expect(xml).not_to include("app:")
          # Should not have redundant xmlns:app
          expect(xml).not_to include("xmlns:app=")
        end
      end

      describe "round-trip compatibility" do
        it "parses both prefixed and default namespace XML" do
          # Generate with default namespace
          xml_default = instance.to_xml
          parsed_default = properties_class.from_xml(xml_default)

          # Generate with prefix
          xml_prefixed = instance.to_xml(prefix: true)
          parsed_prefixed = properties_class.from_xml(xml_prefixed)

          # Both should parse to same data
          expect(parsed_default.template).to eq("Normal.dotm")
          expect(parsed_prefixed.template).to eq("Normal.dotm")
          expect(parsed_default.template).to eq(parsed_prefixed.template)
        end
      end
    end

    context "with non-namespaced model attribute" do
      # Define test model
      let(:properties_class) do
        ns = app_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :template, :string

          xml do
            element "Properties"
            namespace ns
            map_element "Template", to: :template
          end

          def self.name
            "Properties"
          end
        end
      end

      let(:instance) { properties_class.new(template: "Normal.dotm") }

      describe "default behavior (no prefix option)" do
        # Rationale: Because the model attribute is a default type (string)
        # without namespace, we treat it the same as namespaced attribute (because
        # a :string won't be expected to be of a different namespace).

        # Target behavior: Should use default namespace (no prefix)
        # Current behavior: Uses prefix (app:) with both xmlns and xmlns:app
        it "uses default namespace (xmlns='...')" do
          xml = instance.to_xml

          # Should have only xmlns, no xmlns:app
          expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<Template>Normal.dotm</Template>")
          expect(xml).not_to include("app:")
          expect(xml).not_to include("xmlns:app=")
        end
      end

      describe "prefix: true" do
        # Using prefix includes both default and prefixed xmlns (valid but redundant per W3C)
        it "uses defined prefix_default" do
          xml = instance.to_xml(prefix: true)

          # Should have xmlns:app and use the prefix
          expect(xml).to include('<app:Properties xmlns:app="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<app:Template>Normal.dotm</app:Template>")
        end
      end

      describe "prefix: 'custom'" do
        # Custom prefix support not yet implemented - uses default prefix_default instead
        it "uses custom prefix string" do
          xml = instance.to_xml(prefix: "custom")

          expect(xml).to include('<custom:Properties xmlns:custom="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<custom:Template>Normal.dotm</custom:Template>")
          # Should not have redundant declarations
          expect(xml).not_to match(/xmlns="/)
          expect(xml).not_to match(/xmlns:app=/)
        end
      end

      describe "prefix: false" do
        # Target behavior: Should use default namespace explicitly
        # Current behavior: Uses default namespace but still declares xmlns:app
        it "explicitly uses default namespace" do
          xml = instance.to_xml(prefix: false)

          expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<Template>Normal.dotm</Template>")
          expect(xml).not_to include("app:")
          # Should not have redundant xmlns:app
          expect(xml).not_to include("xmlns:app=")
        end
      end

      describe "prefix: nil" do
        # Target behavior: Should use default namespace (same as prefix: false)
        # Current behavior: Uses default namespace but still declares xmlns:app
        it "explicitly uses default namespace" do
          xml = instance.to_xml(prefix: nil)

          expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">')
          expect(xml).to include("<Template>Normal.dotm</Template>")
          expect(xml).not_to include("app:")
          # Should not have redundant xmlns:app
          expect(xml).not_to include("xmlns:app=")
        end
      end

      describe "round-trip compatibility" do
        it "parses both prefixed and default namespace XML" do
          # Generate with default namespace
          xml_default = instance.to_xml
          parsed_default = properties_class.from_xml(xml_default)

          # Generate with prefix
          xml_prefixed = instance.to_xml(prefix: true)
          parsed_prefixed = properties_class.from_xml(xml_prefixed)

          # Both should parse to same data
          expect(parsed_default.template).to eq("Normal.dotm")
          expect(parsed_prefixed.template).to eq("Normal.dotm")
          expect(parsed_default.template).to eq(parsed_prefixed.template)
        end
      end
    end
  end

  context "with Nokogiri adapter" do
    it_behaves_like "prefix control behavior", Lutaml::Model::Xml::NokogiriAdapter
  end

  context "with Ox adapter" do
    it_behaves_like "prefix control behavior", Lutaml::Model::Xml::OxAdapter
  end
end
