# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::XmlNamespace do
  describe "class methods" do
    let(:namespace_class) do
      Class.new(described_class) do
        uri "https://example.com/ns"
        schema_location "https://example.com/ns.xsd"
        prefix_default "ex"
      end
    end

    describe ".uri" do
      it "sets and gets the namespace URI" do
        expect(namespace_class.uri).to eq("https://example.com/ns")
      end

      it "returns nil when not set" do
        empty_class = Class.new(described_class)
        expect(empty_class.uri).to be_nil
      end
    end

    describe ".schema_location" do
      it "sets and gets the schema location" do
        expect(namespace_class.schema_location).to eq("https://example.com/ns.xsd")
      end

      it "returns nil when not set" do
        empty_class = Class.new(described_class)
        expect(empty_class.schema_location).to be_nil
      end
    end

    describe ".prefix_default" do
      it "sets and gets the default prefix as string" do
        expect(namespace_class.prefix_default).to eq("ex")
      end

      it "converts symbol to string" do
        ns_class = Class.new(described_class) do
          prefix_default :test
        end
        expect(ns_class.prefix_default).to eq("test")
      end

      it "returns nil when not set" do
        empty_class = Class.new(described_class)
        expect(empty_class.prefix_default).to be_nil
      end
    end

    describe ".element_form_default" do
      it "defaults to :unqualified" do
        empty_class = Class.new(described_class)
        expect(empty_class.element_form_default).to eq(:unqualified)
      end

      it "sets and gets :qualified" do
        ns_class = Class.new(described_class) do
          element_form_default :qualified
        end
        expect(ns_class.element_form_default).to eq(:qualified)
      end

      it "sets and gets :unqualified" do
        ns_class = Class.new(described_class) do
          element_form_default :unqualified
        end
        expect(ns_class.element_form_default).to eq(:unqualified)
      end

      it "raises error for invalid value" do
        expect do
          Class.new(described_class) do
            element_form_default :invalid
          end
        end.to raise_error(ArgumentError, /qualified or :unqualified/)
      end
    end

    describe ".attribute_form_default" do
      it "defaults to :unqualified" do
        empty_class = Class.new(described_class)
        expect(empty_class.attribute_form_default).to eq(:unqualified)
      end

      it "sets and gets :qualified" do
        ns_class = Class.new(described_class) do
          attribute_form_default :qualified
        end
        expect(ns_class.attribute_form_default).to eq(:qualified)
      end

      it "raises error for invalid value" do
        expect do
          Class.new(described_class) do
            attribute_form_default "wrong"
          end
        end.to raise_error(ArgumentError, /qualified or :unqualified/)
      end
    end

    describe ".imports" do
      let(:other_namespace) do
        Class.new(described_class) do
          uri "https://example.com/other"
        end
      end

      it "adds imported namespaces" do
        ns_class = Class.new(described_class)
        ns_class.imports(other_namespace)
        expect(ns_class.imports).to eq([other_namespace])
      end

      it "accumulates multiple imports" do
        another_namespace = Class.new(described_class) do
          uri "https://example.com/another"
        end

        ns_class = Class.new(described_class)
        ns_class.imports(other_namespace)
        ns_class.imports(another_namespace)

        expect(ns_class.imports).to match_array([other_namespace, another_namespace])
      end

      it "raises error for non-XmlNamespace class" do
        expect do
          Class.new(described_class) do
            imports String
          end
        end.to raise_error(ArgumentError, /requires XmlNamespace classes/)
      end

      it "returns empty array when nothing imported" do
        empty_class = Class.new(described_class)
        expect(empty_class.imports).to eq([])
      end
    end

    describe ".includes" do
      it "adds included schema locations" do
        ns_class = Class.new(described_class) do
          includes "common.xsd"
        end
        expect(ns_class.includes).to eq(["common.xsd"])
      end

      it "accumulates multiple includes" do
        ns_class = Class.new(described_class) do
          includes "common.xsd"
          includes "extensions.xsd"
        end
        expect(ns_class.includes).to match_array(["common.xsd", "extensions.xsd"])
      end

      it "raises error for non-string" do
        expect do
          Class.new(described_class) do
            includes 123
          end
        end.to raise_error(ArgumentError, /String schema locations/)
      end

      it "returns empty array when nothing included" do
        empty_class = Class.new(described_class)
        expect(empty_class.includes).to eq([])
      end
    end

    describe ".version" do
      it "sets and gets the version" do
        ns_class = Class.new(described_class) do
          version "1.0"
        end
        expect(ns_class.version).to eq("1.0")
      end

      it "returns nil when not set" do
        empty_class = Class.new(described_class)
        expect(empty_class.version).to be_nil
      end
    end

    describe ".documentation" do
      it "sets and gets documentation text" do
        ns_class = Class.new(described_class) do
          documentation "Test documentation"
        end
        expect(ns_class.documentation).to eq("Test documentation")
      end

      it "returns nil when not set" do
        empty_class = Class.new(described_class)
        expect(empty_class.documentation).to be_nil
      end
    end

    describe ".annotation" do
      it "stores annotation block" do
        block = proc { "test" }
        ns_class = Class.new(described_class)
        ns_class.annotation(&block)
        expect(ns_class.annotation).to eq(block)
      end
    end

    describe ".build" do
      it "creates instance with default prefix" do
        instance = namespace_class.build
        expect(instance.prefix).to eq("ex")
      end

      it "creates instance with custom prefix" do
        instance = namespace_class.build(prefix: "custom")
        expect(instance.prefix).to eq("custom")
      end
    end
  end

  describe "instance methods" do
    let(:namespace_class) do
      Class.new(described_class) do
        uri "https://example.com/ns"
        schema_location "https://example.com/ns.xsd"
        prefix_default "ex"
        element_form_default :qualified
        attribute_form_default :unqualified
        version "1.0"
        documentation "Test namespace"
      end
    end

    let(:instance) { namespace_class.new }

    describe "#initialize" do
      it "resolves all class-level metadata" do
        expect(instance.uri).to eq("https://example.com/ns")
        expect(instance.schema_location).to eq("https://example.com/ns.xsd")
        expect(instance.prefix).to eq("ex")
        expect(instance.element_form_default).to eq(:qualified)
        expect(instance.attribute_form_default).to eq(:unqualified)
        expect(instance.version).to eq("1.0")
        expect(instance.documentation).to eq("Test namespace")
      end

      it "allows prefix override" do
        custom_instance = namespace_class.new(prefix: "custom")
        expect(custom_instance.prefix).to eq("custom")
      end

      it "converts symbol prefix to string" do
        custom_instance = namespace_class.new(prefix: :sym)
        expect(custom_instance.prefix).to eq("sym")
      end
    end

    describe "#attr_name" do
      it "returns xmlns:prefix for prefixed namespace" do
        expect(instance.attr_name).to eq("xmlns:ex")
      end

      it "returns xmlns for unprefixed namespace" do
        unprefixed_class = Class.new(described_class) do
          uri "https://example.com/ns"
        end
        unprefixed_instance = unprefixed_class.new
        expect(unprefixed_instance.attr_name).to eq("xmlns")
      end

      it "returns xmlns for empty prefix" do
        empty_prefix = namespace_class.new(prefix: "")
        expect(empty_prefix.attr_name).to eq("xmlns")
      end
    end

    describe "#prefixed?" do
      it "returns true when prefix is set" do
        expect(instance.prefixed?).to be true
      end

      it "returns false when prefix is nil" do
        unprefixed_class = Class.new(described_class) do
          uri "https://example.com/ns"
        end
        unprefixed_instance = unprefixed_class.new
        expect(unprefixed_instance.prefixed?).to be false
      end

      it "returns false when prefix is empty string" do
        empty_prefix = namespace_class.new(prefix: "")
        expect(empty_prefix.prefixed?).to be false
      end
    end

    describe "#elements_qualified?" do
      it "returns true when element_form_default is :qualified" do
        expect(instance.elements_qualified?).to be true
      end

      it "returns false when element_form_default is :unqualified" do
        unqualified_class = Class.new(described_class) do
          uri "https://example.com/ns"
        end
        unqualified_instance = unqualified_class.new
        expect(unqualified_instance.elements_qualified?).to be false
      end
    end

    describe "#attributes_qualified?" do
      it "returns false when attribute_form_default is :unqualified" do
        expect(instance.attributes_qualified?).to be false
      end

      it "returns true when attribute_form_default is :qualified" do
        qualified_class = Class.new(described_class) do
          uri "https://example.com/ns"
          attribute_form_default :qualified
        end
        qualified_instance = qualified_class.new
        expect(qualified_instance.attributes_qualified?).to be true
      end
    end
  end

  describe "full example" do
    # Define constants to avoid scoping issues
    let(:address_namespace) do
      Class.new(described_class) do
        uri "https://example.com/address"
        prefix_default "addr"
      end
    end

    let(:contact_namespace) do
      addr_ns = address_namespace # Capture in closure
      Class.new(described_class) do
        uri "https://example.com/contact/v1"
        schema_location "https://example.com/contact/v1/contact.xsd"
        prefix_default "contact"
        element_form_default :qualified
        attribute_form_default :unqualified
        version "1.0"
        documentation "Contact information schema"
        includes "contact-common.xsd"
      end.tap do |klass|
        klass.imports(addr_ns) # Add imports after class creation
      end
    end

    it "creates fully configured namespace" do
      instance = contact_namespace.new

      expect(instance.uri).to eq("https://example.com/contact/v1")
      expect(instance.schema_location).to eq("https://example.com/contact/v1/contact.xsd")
      expect(instance.prefix).to eq("contact")
      expect(instance.element_form_default).to eq(:qualified)
      expect(instance.attribute_form_default).to eq(:unqualified)
      expect(instance.version).to eq("1.0")
      expect(instance.documentation).to eq("Contact information schema")
      expect(instance.imports).to eq([address_namespace])
      expect(instance.includes).to eq(["contact-common.xsd"])
      expect(instance.attr_name).to eq("xmlns:contact")
      expect(instance.prefixed?).to be true
      expect(instance.elements_qualified?).to be true
      expect(instance.attributes_qualified?).to be false
    end

    it "allows runtime prefix override" do
      instance = contact_namespace.new(prefix: "c")

      expect(instance.prefix).to eq("c")
      expect(instance.attr_name).to eq("xmlns:c")
      expect(instance.uri).to eq("https://example.com/contact/v1")
    end
  end
end