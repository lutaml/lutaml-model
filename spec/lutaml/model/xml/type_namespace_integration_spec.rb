require "spec_helper"
require "lutaml/model"

RSpec.describe "Type-level namespace integration" do
  # Define test namespaces mirroring Core Properties structure
  let(:cp_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
      prefix_default "cp"
    end
  end

  let(:dc_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://purl.org/dc/elements/1.1/"
      prefix_default "dc"
    end
  end

  let(:dcterms_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://purl.org/dc/terms/"
      prefix_default "dcterms"
    end
  end

  let(:xsi_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://www.w3.org/2001/XMLSchema-instance"
      prefix_default "xsi"
    end
  end

  describe "Type namespace in elements" do
    it "applies type namespace to elements" do
      # Define Type with namespace
      dc_title_type = Class.new(Lutaml::Model::Type::String)
      dc_title_type.xml_namespace(dc_namespace)

      # Define Model
      document_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :title, dc_title_type

        xml do
          root "document"
          map_element "title", to: :title
        end

        def self.name
          "Document"
        end
      end

      # Test serialization
      doc = document_class.new(title: "Test Title")
      xml = doc.to_xml

      # Type namespaces are now integrated in adapters
      expect(xml).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')
      expect(xml).to include("<dc:title>Test Title</dc:title>")
    end

    it "allows explicit namespace to override type namespace" do
      # Capture namespace in local variable for use in blocks
      dc_ns = dc_namespace

      # Define Type with namespace
      dc_title_type = Class.new(Lutaml::Model::Type::String)
      dc_title_type.xml_namespace(dc_ns)

      override_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/override"
        prefix_default "override"
      end

      # Define Model with explicit namespace override
      document_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :title, dc_title_type

        xml do
          root "document"
          # Explicit namespace should override type namespace
          map_element "title", to: :title, namespace: override_ns
        end

        def self.name
          "Document"
        end
      end

      doc = document_class.new(title: "Test Title")
      xml = doc.to_xml

      # Explicit namespace takes priority
      expect(xml).to include('xmlns:override="http://example.com/override"')
      expect(xml).to include("<override:title>Test Title</override:title>")
      expect(xml).not_to include("dc:title")
    end
  end

  describe "Type namespace in attributes" do
    it "applies type namespace to attributes" do
      # Define Type with namespace for attribute
      xsi_type_type = Class.new(Lutaml::Model::Type::String)
      xsi_type_type.xml_namespace(xsi_namespace)

      # Define Model
      document_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :name, :string
        attribute :schema_type, xsi_type_type

        xml do
          root "document"
          map_attribute "name", to: :name
          map_attribute "type", to: :schema_type
        end

        def self.name
          "Document"
        end
      end

      # Test serialization
      doc = document_class.new(name: "test", schema_type: "DocumentType")
      xml = doc.to_xml

      # Unprefixed attribute should have no namespace per W3C
      expect(xml).to include('name="test"')
      expect(xml).not_to include("xsi:name")

      # Type namespace for attributes is now integrated
      expect(xml).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      expect(xml).to include('xsi:type="DocumentType"')
    end

    it "unprefixed attributes have no namespace per W3C" do
      # Define Model with mix of namespace and plain attributes
      document_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :id, :string
        attribute :title, :string

        xml do
          root "document"
          map_attribute "id", to: :id
          map_attribute "title", to: :title
        end

        def self.name
          "Document"
        end
      end

      doc = document_class.new(id: "doc1", title: "Test")
      xml = doc.to_xml

      # Both should be unprefixed (no namespace per W3C)
      expect(xml).to include('id="doc1"')
      expect(xml).to include('title="Test"')
      # Should not have any namespace prefix
      expect(xml).not_to match(/:id=/)
      expect(xml).not_to match(/:title=/)
    end
  end

  describe "Multiple namespaces in one document" do
    it "handles multiple type namespaces correctly" do
      # Define multiple Types with different namespaces
      dc_title_type = Class.new(Lutaml::Model::Type::String)
      dc_title_type.xml_namespace(dc_namespace)

      dc_creator_type = Class.new(Lutaml::Model::Type::String)
      dc_creator_type.xml_namespace(dc_namespace)

      cp_revision_type = Class.new(Lutaml::Model::Type::Integer)
      cp_revision_type.xml_namespace(cp_namespace)

      # Get the namespace URIs for use in xml block
      cp_uri = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"

      # Define Model
      document_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :title, dc_title_type
        attribute :creator, dc_creator_type
        attribute :revision, cp_revision_type

        xml do
          root "coreProperties"
          namespace cp_uri, "cp"
          map_element "title", to: :title
          map_element "creator", to: :creator
          map_element "revision", to: :revision
        end

        def self.name
          "CoreProperties"
        end
      end

      # Test serialization
      doc = document_class.new(
        title: "Test Document",
        creator: "Test Author",
        revision: 1,
      )
      xml = doc.to_xml

      # Should include both namespaces
      expect(xml).to include('xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"')
      expect(xml).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')

      # Should use correct prefixes
      expect(xml).to include("<dc:title>")
      expect(xml).to include("<dc:creator>")
      expect(xml).to include("<cp:revision>")
    end
  end

  describe "Model namespace vs Type namespace" do
    it "type namespace takes precedence for attributes" do
      # Define Type with namespace
      special_type = Class.new(Lutaml::Model::Type::String)
      special_type.xml_namespace(dc_namespace)

      # Define Model with different namespace
      model_namespace = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/model"
        prefix_default "model"
      end

      document_class = Class.new do
        include Lutaml::Model::Serialize

        namespace model_namespace
        attribute :special_field, special_type

        xml do
          root "document"
          map_element "special_field", to: :special_field
        end

        def self.name
          "Document"
        end
      end

      doc = document_class.new(special_field: "value")
      xml = doc.to_xml

      # Element should use Type namespace (dc), not model namespace
      expect(xml).to include("<dc:special_field>")
      expect(xml).not_to include("<model:special_field>")
    end
  end

  describe "Round-trip serialization" do
    it "deserializes namespaced elements correctly" do
      # Define Type with namespace
      dc_title_type = Class.new(Lutaml::Model::Type::String)
      dc_title_type.xml_namespace(dc_namespace)

      # Define Model
      document_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :title, dc_title_type

        xml do
          root "document"
          map_element "title", to: :title
        end

        def self.name
          "Document"
        end
      end

      # Create and serialize
      original = document_class.new(title: "Round Trip Test")
      xml = original.to_xml

      # Verify serialization has namespace
      expect(xml).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')
      expect(xml).to include("<dc:title>Round Trip Test</dc:title>")

      # Deserialize
      parsed = document_class.from_xml(xml)

      # Verify round-trip
      expect(parsed.title).to eq("Round Trip Test")
      expect(parsed).to eq(original)
    end
  end
end
