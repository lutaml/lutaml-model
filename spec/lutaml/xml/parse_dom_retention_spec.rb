# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML parse DOM retention" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :item, :string

      xml do
        element "root"
        map_element "item", to: :item
      end
    end
  end

  let(:xml) do
    <<~XML
      <root xmlns:xyz="http://example.com/items">
        <xyz:item>hello</xyz:item>
      </root>
    XML
  end

  it "does not retain the adapter root element after parsing" do
    model = model_class.from_xml(xml)
    expect(model.pending_plan_root_element).to be_nil
  end

  it "still captures the input namespace declarations" do
    model = model_class.from_xml(xml)
    expect(model.import_declaration_plan).to be_a(Lutaml::Xml::DeclarationPlan)
  end
end
