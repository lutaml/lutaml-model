# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Transform with dynamically added attributes" do
  before do
    Lutaml::Model::GlobalContext.clear_caches
  end

  it "picks up attributes added after initial class definition" do
    base_class = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        element "test"
        map_element "name", to: :name
      end

      def self.name
        "DynamicAttributeTestClass"
      end
    end

    # Parse once to populate Transform cache
    base_class.from_xml("<test><name>initial</name></test>")

    # Dynamically add a new attribute and mapping (like xmi EaRoot.load_extension)
    base_class.class_eval do
      attribute :extra, :string

      xml do
        map_element "extra", to: :extra
      end
    end

    # The Transform must see the newly added attribute
    result = base_class.from_xml("<test><name>hello</name><extra>world</extra></test>")
    expect(result.name).to eq("hello")
    expect(result.extra).to eq("world")
  end
end
