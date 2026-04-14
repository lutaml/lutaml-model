# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml"

RSpec.describe Lutaml::Xml::CustomMethodWrapper do
  describe "#add_element" do
    it "parses XML fragments through Moxml when Opal is active" do
      parent = Lutaml::Xml::DataModel::XmlElement.new("parent")
      wrapper = described_class.new(parent, nil)

      allow(Lutaml::Model::RuntimeCompatibility).to receive(:opal?)
        .and_return(true)

      wrapper.add_element(
        parent,
        "<a title=\"copyright\">one</a><b>two</b>",
      )

      expect(parent.raw_content).to be_nil
      expect(parent.children.map(&:name)).to eq(%w[a b])
      expect(parent.children[0].attributes.first.value).to eq("copyright")
      expect(parent.children[0].text_content).to eq("one")
      expect(parent.children[1].text_content).to eq("two")
    end
  end

  describe "RuleApplier integration" do
    it "loads the wrapper through the public XML autoload path" do
      parent = Lutaml::Xml::DataModel::XmlElement.new("parent")
      model_class = Class.new do
        def custom_to_xml(_model, parent, wrapper)
          wrapper.add_text(parent, "ok")
        end
      end
      rule = Struct.new(:custom_methods).new({ to: :custom_to_xml })
      applier = Class.new do
        include Lutaml::Xml::TransformationSupport::RuleApplier

        public :apply_custom_method
      end.new

      applier.apply_custom_method(parent, rule, model_class, Object.new)

      expect(parent.text_content).to eq("ok")
    end
  end
end
