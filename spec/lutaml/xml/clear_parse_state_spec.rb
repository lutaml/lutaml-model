# frozen_string_literal: true

require "spec_helper"

RSpec.describe "#clear_xml_parse_state!" do
  before do
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
  end

  let(:ns_class) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/items"
      prefix_default "a"
    end
  end

  let(:model_class) do
    ns = ns_class
    Class.new(Lutaml::Model::Serializable) do
      attribute :item, :string
      attribute :count, :integer

      xml do
        element "root"
        namespace ns
        map_element "item", to: :item
        map_attribute "count", to: :count
      end
    end
  end

  let(:xml_with_ns) do
    <<~XML
      <root xmlns:xyz="http://example.com/items" count="3">
        <xyz:item>hello</xyz:item>
      </root>
    XML
  end

  describe "clearing parse state" do
    it "clears import_declaration_plan set by :eager mode" do
      model = model_class.from_xml(xml_with_ns, import_declaration_plan: :eager)
      expect(model.import_declaration_plan).to be_a(Lutaml::Xml::DeclarationPlan)
      model.clear_xml_parse_state!
      expect(model.import_declaration_plan).to be_nil
    end

    it "clears pending_plan_root_element set by :lazy mode" do
      model = model_class.from_xml(xml_with_ns)
      expect(model.pending_plan_root_element).not_to be_nil
      model.clear_xml_parse_state!
      expect(model.pending_plan_root_element).to be_nil
    end
  end

  describe "return value" do
    it "returns self for chaining" do
      model = model_class.from_xml(xml_with_ns)
      expect(model.clear_xml_parse_state!).to equal(model)
    end
  end

  describe "idempotency" do
    it "is safe to call multiple times" do
      model = model_class.from_xml(xml_with_ns)
      expect { 3.times { model.clear_xml_parse_state! } }.not_to raise_error
    end

    it "is safe on freshly created instances with no parse state" do
      model = model_class.new(item: "test", count: 1)
      expect { model.clear_xml_parse_state! }.not_to raise_error
    end
  end

  describe "user-facing attributes" do
    it "clears element_order to release parse buffers" do
      model = model_class.from_xml(xml_with_ns)
      expect(model.element_order).not_to be_nil
      model.clear_xml_parse_state!
      expect(model.element_order).to be_nil
    end

    it "clears attribute_order to release parse buffers" do
      model = model_class.from_xml(xml_with_ns)
      expect(model.attribute_order).not_to be_nil
      model.clear_xml_parse_state!
      expect(model.attribute_order).to be_nil
    end

    it "does not clear encoding" do
      model = model_class.from_xml(xml_with_ns, encoding: "UTF-8")
      model.clear_xml_parse_state!
      expect(model.encoding).to eq("UTF-8")
    end

    it "does not clear model attributes" do
      model = model_class.from_xml(xml_with_ns)
      expect(model.item).to eq("hello")
      expect(model.count).to eq(3)
      model.clear_xml_parse_state!
      expect(model.item).to eq("hello")
      expect(model.count).to eq(3)
    end
  end

  describe "re-serialization after clearing" do
    it "allows to_xml after clearing parse state" do
      model = model_class.from_xml(xml_with_ns, import_declaration_plan: :eager)
      model.clear_xml_parse_state!
      result = model.to_xml
      expect(result).to include("hello")
    end

    it "allows to_xml after clearing lazy parse state" do
      model = model_class.from_xml(xml_with_ns)
      model.clear_xml_parse_state!
      result = model.to_xml
      expect(result).to include("hello")
    end

    it "reflects model modifications after clearing" do
      model = model_class.from_xml(xml_with_ns)
      model.item = "modified"
      model.clear_xml_parse_state!
      result = model.to_xml
      expect(result).to include("modified")
    end
  end

  describe "Uniword parse-modify-clear-reserialize workflow" do
    it "clears stale namespace state across multiple parts" do
      part1 = model_class.from_xml(xml_with_ns, import_declaration_plan: :eager)
      part2 = model_class.from_xml(xml_with_ns, import_declaration_plan: :eager)

      part1.item = "reconciled"
      part2.item = "also reconciled"

      [part1, part2].each(&:clear_xml_parse_state!)

      expect(part1.to_xml).to include("reconciled")
      expect(part2.to_xml).to include("also reconciled")
    end
  end
end
