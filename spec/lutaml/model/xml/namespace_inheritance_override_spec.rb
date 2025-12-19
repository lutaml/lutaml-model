# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

# Namespace Inheritance and Override Spec
# Tests how child classes can modify or remove parent class namespaces
RSpec.describe "Namespace Inheritance and Override" do
  let(:parent_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/parent"
      prefix_default "parent"
    end
  end

  let(:child_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/child"
      prefix_default "child"
    end
  end

  context "removing namespace from base class" do
    let(:base_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "base"
          namespace ns
          map_element "name", to: :name
        end
      end
    end

    context "using namespace nil" do
      let(:child_model) do
        Class.new(base_model) do
          xml do
            element "child"
            namespace nil  # Explicitly NO namespace
            # Inherits mappings from base
          end
        end
      end

      it "child has NO namespace (removes parent's namespace)" do
        child = child_model.new(name: "test")
        xml = child.to_xml

        # namespace nil should mean "explicitly blank namespace"
        # Child should not have any xmlns declaration
        expected = <<~XML.chomp
          <child>
            <name>test</name>
          </child>
        XML

        expect(xml).to match(expected)
      end

      it "child serializes without parent namespace in context" do
        child = child_model.new(name: "test")
        xml = child.to_xml

        # Should not contain parent namespace URI
        expect(xml).not_to include("http://example.com/parent")
      end
    end

    context "using namespace with empty string URI" do
      let(:child_model) do
        Class.new(base_model) do
          xml do
            element "child"
            namespace :blank  # Empty string URI = blank namespace
          end
        end
      end

      it "child has blank namespace (empty URI)" do
        child = child_model.new(name: "test")
        xml = child.to_xml

        # namespace :blank creates blank namespace (no xmlns)
        # Semantically same as namespace nil for practical purposes
        expected = <<~XML.chomp
          <child>
            <name>test</name>
          </child>
        XML

        expect(xml).to match(expected)
      end
    end

    context "semantic difference between nil and empty string" do
      let(:nil_model) do
        Class.new(base_model) do
          xml do
            element "nil_child"
            namespace nil  # Explicit NO namespace
          end
        end
      end

      let(:empty_model) do
        Class.new(base_model) do
          xml do
            element "empty_child"
            namespace :blank  # Blank namespace (empty URI)
          end
        end
      end

      it "both nil and empty string result in no namespace" do
        nil_xml = nil_model.new(name: "test").to_xml
        empty_xml = empty_model.new(name: "test").to_xml

        # Both should produce XML without namespace
        expect(nil_xml).not_to include("xmlns")
        expect(empty_xml).not_to include("xmlns")

        # Both should not reference parent namespace
        expect(nil_xml).not_to include("http://example.com/parent")
        expect(empty_xml).not_to include("http://example.com/parent")
      end
    end
  end

  context "changing namespace in inheriting class" do
    let(:base_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "base"
          namespace ns
          map_element "name", to: :name
        end
      end
    end

    let(:child_model) do
      ns = child_namespace
      Class.new(base_model) do
        xml do
          element "child"
          namespace ns  # Override with different namespace
        end
      end
    end

    it "child uses its own namespace, not parent's" do
      child = child_model.new(name: "test")
      xml = child.to_xml

      # W3C Rule: When child changes root namespace, inherited element mappings
      # retain their original namespace context (blank in this case).
      # The xmlns="" explicitly opts out of inheriting child's default namespace.
      expected = <<~XML.chomp
        <child xmlns="http://example.com/child">
          <name xmlns="">test</name>
        </child>
      XML

      expect(xml).to match(expected)
      expect(xml).not_to include("http://example.com/parent")
    end
  end

  context "nested inheritance with namespace changes" do
    let(:grandparent_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "grandparent"
          namespace ns
          map_element "value", to: :value
        end
      end
    end

    let(:parent_model) do
      Class.new(grandparent_model) do
        xml do
          element "parent"
          namespace :blank  # Remove grandparent's namespace
        end
      end
    end

    let(:child_model) do
      ns = child_namespace
      Class.new(parent_model) do
        xml do
          element "child"
          namespace ns  # Add new namespace
        end
      end
    end

    it "grandparent → parent removes → child adds different namespace" do
      child = child_model.new(value: "test")
      xml = child.to_xml

      # W3C Rule: Inherited element mapping "value" was in blank namespace
      # from parent. When child adds a different namespace, the inherited
      # mapping stays in blank namespace and requires xmlns="" to opt out.
      expected = <<~XML.chomp
        <child xmlns="http://example.com/child">
          <value xmlns="">test</value>
        </child>
      XML

      expect(xml).to match(expected)
      # Should not have grandparent's namespace
      expect(xml).not_to include("http://example.com/parent")
    end
  end

  context "namespace override with element mappings" do
    let(:base_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :data, :string

        xml do
          element "base"
          namespace ns
          map_element "data", to: :data
        end
      end
    end

    let(:child_model) do
      Class.new(base_model) do
        attribute :extra, :string

        xml do
          element "child"
          namespace :blank  # Remove namespace
          # Add new mapping
          map_element "extra", to: :extra
        end
      end
    end

    it "child without namespace, inherits mappings from base" do
      child = child_model.new(data: "original", extra: "new")
      xml = child.to_xml

      # Child has no namespace, inherits mapping for "data"
      expected = <<~XML.chomp
        <child>
          <data>original</data>
          <extra>new</extra>
        </child>
      XML

      expect(xml).to match(expected)
    end
  end

  context "partial namespace override in inheritance" do
    let(:base_model) do
      ns = parent_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :base_attr, :string
        attribute :content, :string

        xml do
          element "base"
          namespace ns
          map_attribute "base_attr", to: :base_attr
          map_content to: :content
        end
      end
    end

    let(:child_model) do
      ns = child_namespace
      Class.new(base_model) do
        attribute :child_attr, :string

        xml do
          element "child"
          namespace ns  # Different namespace
          # Inherits base_attr mapping but with new namespace context
          map_attribute "child_attr", to: :child_attr
        end
      end
    end

    it "child namespace applies to both inherited and new mappings" do
      child = child_model.new(
        base_attr: "base_val",
        child_attr: "child_val",
        content: "text"
      )
      xml = child.to_xml(prefix: true)

      # Both attributes now in child namespace context
      # (assuming attributeFormDefault: :unqualified, no prefix on attrs in same ns)
      expected = <<~XML.chomp
        <child:child xmlns:child="http://example.com/child" base_attr="base_val" child_attr="child_val">text</child:child>
      XML

      expect(xml).to match(expected)
    end
  end
end