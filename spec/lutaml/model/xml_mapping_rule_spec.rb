require "spec_helper"

require "lutaml/model/xml_adapter/ox_adapter"
require "lutaml/model/xml_adapter/oga_adapter"

require_relative "../../../lib/lutaml/model/xml_mapping_rule"

def content_to_xml(model, parent, doc)
  content = model.all_content.sub(/^<div>/, "").sub(/<\/div>$/, "")
  doc.add_xml_fragment(parent, content)
end

def content_from_xml(model, value)
  model.all_content = "<div>#{value}</div>"
end

RSpec.describe Lutaml::Model::XmlMappingRule do
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
