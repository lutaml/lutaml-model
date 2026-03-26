# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Namespace alias support" do
  before do
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
    Lutaml::Xml::NamespaceClassRegistry.instance.clear!
  end

  describe "uri_aliases DSL" do
    it "allows defining multiple URI aliases for a namespace" do
      ns_class = Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/schema/main.xsd"
        uri_aliases "http://example.com/schema/", "http://example.com/schema"
        prefix_default "ex"
      end

      expect(ns_class.uri).to eq("http://example.com/schema/main.xsd")
      expect(ns_class.uri_aliases).to eq(["http://example.com/schema/", "http://example.com/schema"])
      expect(ns_class.all_uris).to eq([
                                        "http://example.com/schema/main.xsd",
                                        "http://example.com/schema/",
                                        "http://example.com/schema",
                                      ])
    end

    it "raises error for non-string alias" do
      expect do
        Class.new(Lutaml::Xml::Namespace) do
          uri "http://example.com/ns"
          uri_aliases 123
        end
      end.to raise_error(ArgumentError,
                         "uri_aliases requires non-empty String URIs")
    end

    it "raises error for empty alias" do
      expect do
        Class.new(Lutaml::Xml::Namespace) do
          uri "http://example.com/ns"
          uri_aliases ""
        end
      end.to raise_error(ArgumentError,
                         "uri_aliases requires non-empty String URIs")
    end

    it "is_alias? returns true for alias URIs" do
      ns_class = Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/schema/main.xsd"
        uri_aliases "http://example.com/schema/"
        prefix_default "ex"
      end

      expect(ns_class.is_alias?("http://example.com/schema/")).to be true
      expect(ns_class.is_alias?("http://example.com/schema")).to be false
      expect(ns_class.is_alias?("http://example.com/schema/main.xsd")).to be false
    end
  end

  describe "NamespaceClassRegistry alias lookup" do
    let(:ns_class) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/schema/main.xsd"
        uri_aliases "http://example.com/schema/"
        prefix_default "ex"
      end
    end

    before do
      Lutaml::Xml::NamespaceClassRegistry.instance.register_named(ns_class)
    end

    it "find_by_uri_or_alias finds by canonical URI" do
      found = Lutaml::Xml::NamespaceClassRegistry.instance.find_by_uri_or_alias("http://example.com/schema/main.xsd")
      expect(found).to eq(ns_class)
    end

    it "find_by_uri_or_alias finds by alias URI" do
      found = Lutaml::Xml::NamespaceClassRegistry.instance.find_by_uri_or_alias("http://example.com/schema/")
      expect(found).to eq(ns_class)
    end
  end

  describe "parsing XML with namespace aliases" do
    let(:ns_class) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/items"
        uri_aliases "http://example.com/items/"
        prefix_default "a"
      end
    end

    let(:model_class) do
      ns = ns_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :item, :string

        xml do
          root "root"
          namespace ns
          map_element "item", to: :item
        end
      end
    end

    it "parses XML with alias URI and round-trips" do
      xml = <<~XML
        <root xmlns="http://example.com/items/">
          <item>hello</item>
        </root>
      XML

      model = model_class.from_xml(xml)
      expect(model.item).to eq("hello")

      # Round-trip should preserve the alias URI via default namespace
      output = model.to_xml
      expect(output).to include('xmlns="http://example.com/items/"')
      expect(output).to include("<item xmlns=\"\">hello</item>")
    end

    it "round-trips alias URI through serialization with prefixed namespace" do
      xml = <<~XML
        <root xmlns:a="http://example.com/items/">
          <a:item>hello</a:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      output = model.to_xml

      # Should preserve the original alias URI in the prefixed namespace declaration
      expect(output).to include('xmlns:a="http://example.com/items/"')
      # Note: Child element format depends on namespace inheritance - the test verifies
      # that the alias URI is preserved in the xmlns declarations
    end

    it "can parse canonical URI and serialize with alias" do
      xml = <<~XML
        <root xmlns:a="http://example.com/items">
          <a:item>hello</a:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      expect(model.item).to eq("hello")

      # Round-trip with default prefix format
      output = model.to_xml
      expect(output).to include('xmlns:a="http://example.com/items"')
      expect(output).to include("<a:item>hello</a:item>")
    end
  end

  describe "nested models with namespace aliases" do
    let(:ns_class) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/items"
        uri_aliases "http://example.com/items/"
        prefix_default "a"
      end
    end

    let(:inner_class) do
      ns = ns_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          root "Inner"
          namespace ns
          map_element "name", to: :name
        end
      end
    end

    let(:outer_class) do
      ns = ns_class
      ic = inner_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :child, ic

        xml do
          root "Outer"
          namespace ns
          map_element "Inner", to: :child
        end
      end
    end

    it "preserves alias URI for nested model element" do
      xml = <<~XML
        <Outer xmlns:xyzabc="http://example.com/items/">
          <xyzabc:Inner><xyzabc:name>from alias</xyzabc:name></xyzabc:Inner>
        </Outer>
      XML

      model = outer_class.from_xml(xml)
      expect(model.child.name).to eq("from alias")

      # Verify original namespace URI is stored in DeclarationPlan
      stored_plan = model.__input_declaration_plan
      expect(stored_plan&.original_namespace_uris).to eq(
        { "http://example.com/items" => "http://example.com/items/" },
      )

      output = model.to_xml
      expect(output).to include('xmlns:xyzabc="http://example.com/items/"')
      expect(output).to include("<xyzabc:Inner>")
      expect(output).to include("<xyzabc:name>from alias</xyzabc:name>")
    end
  end

  describe "mixed content with namespace aliases" do
    let(:parent_ns_class) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/parent"
        uri_aliases "http://example.com/parent/"
        prefix_default "p"
      end
    end

    let(:child_ns_class) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/child"
        uri_aliases "http://example.com/child/"
        prefix_default "c"
      end
    end

    let(:parent_class) do
      pns = parent_ns_class
      cns = child_ns_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :child_name, :string

        xml do
          root "Parent"
          namespace pns
          map_element "childName", to: :child_name
          namespace cns
        end
      end
    end

    it "round-trips mixed content with alias URIs" do
      xml = <<~XML
        <p:Parent xmlns:p="http://example.com/parent/">
          <c:childName xmlns:c="http://example.com/child/">mixed content</c:childName>
        </p:Parent>
      XML

      model = parent_class.from_xml(xml)
      expect(model.child_name).to eq("mixed content")

      output = model.to_xml
      # Verify alias URIs are preserved - check that the alias URIs appear in xmlns declarations
      expect(output).to include("http://example.com/parent/")
      expect(output).to include("http://example.com/child/")
    end
  end
end
