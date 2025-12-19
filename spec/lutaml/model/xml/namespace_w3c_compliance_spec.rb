# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

# W3C XML Namespace Compliance Spec
# Tests explicit "no namespace" scenarios per W3C specifications
RSpec.describe "W3C Namespace Compliance" do
  # Define test namespaces
  let(:parent_namespace_qualified) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/parent"
      prefix_default "parent"
      element_form_default :qualified
      attribute_form_default :qualified
    end
  end

  let(:parent_namespace_unqualified) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/parent"
      prefix_default "parent"
      element_form_default :unqualified
      attribute_form_default :unqualified
    end
  end

  let(:child_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/child"
      prefix_default "child"
    end
  end

  context "parent with namespace, child element with NO namespace" do
    context "when elementFormDefault is :qualified" do
      let(:no_ns_child_model) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            element "child"
            # Explicit NO namespace
            map_content to: :content
          end
        end
      end

      let(:parent_model) do
        ns = parent_namespace_qualified
        child = no_ns_child_model
        Class.new(Lutaml::Model::Serializable) do
          attribute :child_elem, child

          xml do
            element "parent"
            namespace ns
            # Child element explicitly has NO namespace
            map_element "child", to: :child_elem, namespace: :blank
          end
        end
      end

      it "child element has NO namespace despite parent using namespace" do
        child = no_ns_child_model.new(content: "test")
        parent = parent_model.new(child_elem: child)
        xml = parent.to_xml(prefix: true)

        # Per W3C: namespace: nil means child is in NO namespace
        # Parent uses prefix format, so unprefixed child naturally has no namespace
        expected = <<~XML.chomp
          <parent:parent xmlns:parent="http://example.com/parent">
            <child>test</child>
          </parent:parent>
        XML

        expect(xml).to match(expected)
      end

      it "child element with no namespace when parent uses default format" do
        child = no_ns_child_model.new(content: "test")
        parent = parent_model.new(child_elem: child)
        xml = parent.to_xml

        # Per W3C: namespace: nil with parent using default namespace
        # Child must explicitly declare xmlns="" to remove parent's default
        expected = <<~XML.chomp
          <parent xmlns="http://example.com/parent">
            <child xmlns="">test</child>
          </parent>
        XML

        expect(xml).to match(expected)
      end
    end

    context "when elementFormDefault is :unqualified" do
      let(:no_ns_child_model) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            element "child"
            # No namespace declaration means blank namespace
            map_content to: :content
          end
        end
      end

      let(:parent_model) do
        ns = parent_namespace_unqualified
        child = no_ns_child_model
        Class.new(Lutaml::Model::Serializable) do
          attribute :child_elem, child

          xml do
            element "parent"
            namespace ns
            # Child naturally unqualified (no namespace)
            map_element "child", to: :child_elem
          end
        end
      end

      it "child element has NO namespace (parent uses prefix)" do
        child = no_ns_child_model.new(content: "test")
        parent = parent_model.new(child_elem: child)
        xml = parent.to_xml(prefix: true)

        # elementFormDefault: unqualified means child doesn't inherit parent namespace
        # Parent uses prefix, so unprefixed child is in blank namespace
        expected = <<~XML.chomp
          <parent:parent xmlns:parent="http://example.com/parent">
            <child>test</child>
          </parent:parent>
        XML

        expect(xml).to match(expected)
      end

      it "child element has NO namespace (parent uses default)" do
        child = no_ns_child_model.new(content: "test")
        parent = parent_model.new(child_elem: child)
        xml = parent.to_xml

        # elementFormDefault: unqualified means child doesn't inherit parent namespace
        # Child is naturally in blank namespace, doesn't need xmlns=""
        expected = <<~XML.chomp
          <parent xmlns="http://example.com/parent">
            <child>test</child>
          </parent>
        XML

        expect(xml).to match(expected)
      end
    end
  end

  context "parent with namespace, child XML attribute with NO namespace" do
    context "when attributeFormDefault is :qualified" do
      let(:child_model) do
        ns = child_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string
          attribute :no_ns_attr, :string

          xml do
            element "child"
            namespace ns
            # Attribute explicitly has NO namespace
            map_attribute "no_ns_attr", to: :no_ns_attr, namespace: :blank
            map_content to: :content
          end
        end
      end

      let(:parent_model) do
        ns = parent_namespace_qualified
        child = child_model
        Class.new(Lutaml::Model::Serializable) do
          attribute :child_elem, child

          xml do
            element "parent"
            namespace ns
            map_element "child", to: :child_elem
          end
        end
      end

      it "child attribute has NO namespace despite qualified form default" do
        child = child_model.new(content: "test", no_ns_attr: "value")
        parent = parent_model.new(child_elem: child)
        xml = parent.to_xml

        # Per W3C: namespace: nil on attribute means NO namespace
        # Child element has different namespace URI, uses default format (not prefixed)
        expected = <<~XML.chomp
          <parent xmlns="http://example.com/parent">
            <child xmlns="http://example.com/child" no_ns_attr="value">test</child>
          </parent>
        XML

        expect(xml).to match(expected)
      end
    end

    context "when attributeFormDefault is :unqualified" do
      let(:child_model) do
        ns = child_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string
          attribute :no_ns_attr, :string

          xml do
            element "child"
            namespace ns
            # Attribute has no namespace (blank namespace, default for unqualified)
            map_attribute "no_ns_attr", to: :no_ns_attr
            map_content to: :content
          end
        end
      end

      let(:parent_model) do
        ns = parent_namespace_unqualified
        child = child_model
        Class.new(Lutaml::Model::Serializable) do
          attribute :child_elem, child

          xml do
            element "parent"
            namespace ns
            map_element "child", to: :child_elem
          end
        end
      end

      it "child attribute in blank namespace (no prefix)" do
        child = child_model.new(content: "test", no_ns_attr: "value")
        parent = parent_model.new(child_elem: child)
        xml = parent.to_xml

        # Per W3C: attributeFormDefault: unqualified means attribute is in blank namespace
        # Unprefixed attributes are NEVER in default namespace
        expected = <<~XML.chomp
          <parent xmlns="http://example.com/parent">
            <child xmlns="http://example.com/child" no_ns_attr="value">test</child>
          </parent>
        XML

        expect(xml).to match(expected)
      end
    end
  end

  context "parent with namespace, child with native type value with NO namespace" do
    context "when elementFormDefault is :qualified" do
      let(:parent_model) do
        ns = parent_namespace_qualified
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :value, :string

          xml do
            element "parent"
            namespace ns
            # name inherits parent namespace (qualified)
            map_element "name", to: :name
            # value explicitly has NO namespace
            map_element "value", to: :value, namespace: :blank
          end
        end
      end

      it "qualified element inherits namespace, explicit nil has none (prefix format)" do
        parent = parent_model.new(name: "test", value: "data")
        xml = parent.to_xml(prefix: true)

        # name inherits parent namespace with prefix (qualified)
        # value explicitly has no namespace
        expected = <<~XML.chomp
          <parent:parent xmlns:parent="http://example.com/parent">
            <parent:name>test</parent:name>
            <value>data</value>
          </parent:parent>
        XML

        expect(xml).to match(expected)
      end

      it "qualified element inherits namespace, explicit nil has none (default format)" do
        parent = parent_model.new(name: "test", value: "data")
        xml = parent.to_xml

        # name is schema-qualified, inherits parent's default namespace
        # value must use xmlns="" to explicitly remove default namespace
        expected = <<~XML.chomp
          <parent xmlns="http://example.com/parent">
            <name>test</name>
            <value xmlns="">data</value>
          </parent>
        XML

        expect(xml).to match(expected)
      end
    end

    context "when elementFormDefault is :unqualified" do
      let(:parent_model) do
        ns = parent_namespace_unqualified
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :value, :string

          xml do
            element "parent"
            namespace ns
            # Both elements unqualified by default (no namespace)
            map_element "name", to: :name
            map_element "value", to: :value
          end
        end
      end

      it "unqualified elements have NO namespace (prefix format)" do
        parent = parent_model.new(name: "test", value: "data")
        xml = parent.to_xml(prefix: true)

        # elementFormDefault: unqualified means children don't inherit namespace
        # Parent uses prefix, so unprefixed children are in blank namespace
        expected = <<~XML.chomp
          <parent:parent xmlns:parent="http://example.com/parent">
            <name>test</name>
            <value>data</value>
          </parent:parent>
        XML

        expect(xml).to match(expected)
      end

      it "unqualified elements have NO namespace (default format)" do
        parent = parent_model.new(name: "test", value: "data")
        xml = parent.to_xml

        # elementFormDefault: unqualified + parent uses default namespace
        # Children must explicitly remove with xmlns=""
        expected = <<~XML.chomp
          <parent xmlns="http://example.com/parent">
            <name xmlns="">test</name>
            <value xmlns="">data</value>
          </parent>
        XML

        expect(xml).to match(expected)
      end
    end
  end

  context "mixed scenarios with form overrides" do
    let(:parent_model) do
      ns = parent_namespace_qualified
      Class.new(Lutaml::Model::Serializable) do
        attribute :qualified_elem, :string
        attribute :unqualified_elem, :string
        attribute :qualified_attr, :string
        attribute :unqualified_attr, :string

        xml do
          element "parent"
          namespace ns
          # Override schema default with form option
          map_element "qualified", to: :qualified_elem  # Inherits :qualified
          map_element "unqualified", to: :unqualified_elem, form: :unqualified  # Override
          map_attribute "qualified", to: :qualified_attr  # Inherits :qualified
          map_attribute "unqualified", to: :unqualified_attr, form: :unqualified  # Override
        end
      end
    end

    it "form option overrides schema default (prefix format)" do
      parent = parent_model.new(
        qualified_elem: "q_elem",
        unqualified_elem: "u_elem",
        qualified_attr: "q_attr",
        unqualified_attr: "u_attr"
      )
      xml = parent.to_xml(prefix: true)

      # qualified elements/attrs inherit parent namespace with prefix
      # unqualified elements/attrs have NO namespace (no prefix)
      expected = <<~XML.chomp
        <parent:parent xmlns:parent="http://example.com/parent" parent:qualified="q_attr" unqualified="u_attr">
          <parent:qualified>q_elem</parent:qualified>
          <unqualified>u_elem</unqualified>
        </parent:parent>
      XML

      expect(xml).to match(expected)
    end

    it "form option overrides schema default (default format)" do
      parent = parent_model.new(
        qualified_elem: "q_elem",
        unqualified_elem: "u_elem",
        qualified_attr: "q_attr",
        unqualified_attr: "u_attr"
      )
      xml = parent.to_xml

      # qualified elements inherit parent namespace (default format)
      # qualified attrs use prefix (required for attributes)
      # unqualified elements/attrs have no namespace
      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent" unqualified="u_attr" parent:qualified="q_attr">
          <qualified>q_elem</qualified>
          <unqualified>u_elem</unqualified>
        </parent>
      XML

      expect(xml).to match(expected)
    end
  end

  context "native type attributes with explicit no namespace" do
    let(:parent_model) do
      ns = parent_namespace_qualified
      Class.new(Lutaml::Model::Serializable) do
        attribute :ns_string, :string
        attribute :no_ns_string, :string

        xml do
          element "parent"
          namespace ns
          # ns_string inherits parent namespace (qualified default)
          map_element "ns_string", to: :ns_string
          # no_ns_string explicitly has NO namespace
          map_element "no_ns_string", to: :no_ns_string, namespace: :blank
        end
      end
    end

    it "native type with explicit nil namespace has NO namespace (prefix)" do
      parent = parent_model.new(ns_string: "with_ns", no_ns_string: "without_ns")
      xml = parent.to_xml(prefix: true)

      # ns_string inherits parent namespace
      # no_ns_string explicitly has no namespace
      expected = <<~XML.chomp
        <parent:parent xmlns:parent="http://example.com/parent">
          <parent:ns_string>with_ns</parent:ns_string>
          <no_ns_string>without_ns</no_ns_string>
        </parent:parent>
      XML

      expect(xml).to match(expected)
    end

    it "native type with explicit nil namespace has NO namespace (default)" do
      parent = parent_model.new(ns_string: "with_ns", no_ns_string: "without_ns")
      xml = parent.to_xml

      # ns_string is schema-qualified, inherits default namespace
      # no_ns_string must explicitly remove with xmlns=""
      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent">
          <ns_string>with_ns</ns_string>
          <no_ns_string xmlns="">without_ns</no_ns_string>
        </parent>
      XML

      expect(xml).to match(expected)
    end
  end

  context "combinations of qualified and unqualified with namespaces" do
    let(:typed_attr) do
      ns = child_namespace
      Class.new(Lutaml::Model::Type::String) do
        xml_namespace ns
      end
    end

    let(:parent_model) do
      ns = parent_namespace_qualified
      ta = typed_attr
      Class.new(Lutaml::Model::Serializable) do
        attribute :same_ns_attr, :string
        attribute :diff_ns_attr, ta
        attribute :no_ns_attr, :string

        xml do
          element "parent"
          namespace ns
          # same_ns_attr in parent namespace (qualified form)
          map_attribute "same", to: :same_ns_attr
          # diff_ns_attr in child namespace (different)
          map_attribute "diff", to: :diff_ns_attr
          # no_ns_attr explicitly NO namespace
          map_attribute "none", to: :no_ns_attr, namespace: :blank
        end
      end
    end

    it "handles mix of same, different, and no namespace attributes" do
      parent = parent_model.new(
        same_ns_attr: "same_val",
        diff_ns_attr: "diff_val",
        no_ns_attr: "no_val"
      )
      xml = parent.to_xml

      # Root uses default format (xmlns="..."), not prefix format
      # same: in parent namespace, qualified → needs prefix (can't use default for attrs)
      # diff: in child namespace → needs prefix
      # none: NO namespace → no prefix
      expected = <<~XML.chomp
        <parent xmlns="http://example.com/parent" xmlns:child="http://example.com/child" child:diff="diff_val" none="no_val" parent:same="same_val"/>
      XML

      expect(xml).to match(expected)
    end
  end

  context "W3C edge case: blank namespace vs no namespace" do
    # Per W3C: unprefixed elements/attributes are in "blank" namespace unless
    # a default namespace is declared, which puts them in that namespace

    let(:parent_model) do
      ns = parent_namespace_qualified
      Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "parent"
          namespace ns
          # Content in blank namespace (no namespace declaration)
          map_element "content", to: :content, namespace: :blank
        end
      end
    end

    it "distinguishes between blank namespace and inherited namespace" do
      parent = parent_model.new(content: "test")
      xml_prefix = parent.to_xml(prefix: true)
      xml_default = parent.to_xml

      # Prefix format: unprefixed = blank namespace (no xmlns declaration needed)
      expect(xml_prefix).to include('<content>test</content>')
      expect(xml_prefix).not_to include('xmlns=""')

      # Default format: must explicitly remove default namespace with xmlns=""
      expect(xml_default).to include('<content xmlns="">test</content>')
    end
  end
end