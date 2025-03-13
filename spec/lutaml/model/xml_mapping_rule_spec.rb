require "spec_helper"

require "lutaml/model/xml_adapter/ox_adapter"
require "lutaml/model/xml_adapter/oga_adapter"

require_relative "../../../lib/lutaml/model/mapping/xml_mapping_rule"

def content_to_xml(model, parent, doc)
  content = model.all_content.sub(/^<div>/, "").sub(/<\/div>$/, "")
  doc.add_xml_fragment(parent, content)
end

def content_from_xml(model, value)
  model.all_content = "<div>#{value}</div>"
end

RSpec.describe Lutaml::Model::XmlMappingRule do
  describe "#namespaced_name" do
    let(:namespaced_name) do
      mapping_rule.namespaced_name
    end

    context "when attribute name is string 'lang'" do
      let(:mapping_rule) do
        described_class.new("lang", to: :lang, prefix: "xml")
      end

      it "returns `xml:lang`" do
        expect(namespaced_name).to eq("xml:lang")
      end
    end

    context "when attribute name is symbol ':lang'" do
      let(:mapping_rule) do
        described_class.new(:lang, to: :lang, prefix: "xml")
      end

      it "returns `xml:lang`" do
        expect(namespaced_name).to eq("xml:lang")
      end
    end

    context "when namespace is explicitly set" do
      let(:mapping_rule) do
        described_class.new(
          "explicit_namespace",
          to: :explicit_namespace,
          namespace: "http://test",
          namespace_set: true,
        )
      end

      it "returns `http://test:explicit_namespace`" do
        expect(namespaced_name).to eq("http://test:explicit_namespace")
      end
    end

    context "when namespace is explicitly set to nil" do
      let(:mapping_rule) do
        described_class.new(
          "explicit_namespace",
          to: :explicit_namespace,
          namespace: nil,
          namespace_set: true,
          default_namespace: "http://default",
        )
      end

      it "returns name without namespace" do
        expect(namespaced_name).to eq("explicit_namespace")
      end
    end

    context "when attribute has namespace set" do
      let(:mapping_rule) do
        described_class.new(
          "attribute",
          to: :attribute,
          attribute: true,
          namespace: "http://test",
          default_namespace: "http://default",
        )
      end

      it "returns `http://test:attribute`" do
        expect(namespaced_name).to eq("http://test:attribute")
      end
    end

    context "when attribute has no namespace set" do
      let(:mapping_rule) do
        described_class.new(
          "attribute",
          to: :attribute,
          attribute: true,
          default_namespace: "http://default",
        )
      end

      it "does not use default namespace" do
        expect(namespaced_name).to eq("attribute")
      end
    end

    context "when default_namespace is set" do
      let(:mapping_rule) do
        described_class.new(
          "default_namespace",
          to: :default_namespace,
          default_namespace: "http://default",
        )
      end

      it "returns `default_namespace:name` if not an attribute" do
        expect(namespaced_name).to eq("http://default:default_namespace")
      end
    end
  end

  context "with Xml Mapping Rule" do
    let(:orig_mapping_rule) do
      described_class.new(
        "name",
        to: :name,
        render_nil: true,
        render_default: true,
        with: { to: :content_to_xml, from: :content_from_xml },
        delegate: true,
        namespace: "http://child-namespace",
        prefix: "cn",
        mixed_content: true,
        cdata: true,
        namespace_set: true,
        prefix_set: true,
        attribute: true,
        default_namespace: "http://parent-namespace",
      )
    end

    let(:dup_mapping_rule) do
      orig_mapping_rule.deep_dup
    end

    it "duplicates all instance variables" do
      orig_mapping_rule.instance_variables.each do |variable|
        orig_var = orig_mapping_rule.instance_variable_get(variable)
        dup_var = dup_mapping_rule.instance_variable_get(variable)

        expect(orig_var).to eq(dup_var)
      end
    end
  end
end
