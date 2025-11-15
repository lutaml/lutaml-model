require "spec_helper"
require "lutaml/model"

class RenderNilNested < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String

  xml do
    root "render_nil_nested"

    map_element "name", to: :name
  end
end

class RenderNil < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String, default: -> {
                                                           "Unnamed Pottery"
                                                         }
  attribute :clay_type, Lutaml::Model::Type::String
  attribute :glaze, Lutaml::Model::Type::String
  attribute :dimensions, Lutaml::Model::Type::String, collection: true
  attribute :render_nil_nested, RenderNilNested

  json do
    map "name", to: :name, render_nil: true, render_empty: true
    map "clay_type", to: :clay_type, render_nil: true, render_empty: true
    map "glaze", to: :glaze, render_nil: true, render_empty: true
    map "dimensions", to: :dimensions, render_empty: false
  end

  xml do
    root "render_nil"
    map_element "name", to: :name, render_nil: true, render_empty: true
    map_element "clay_type", to: :clay_type, render_nil: false,
                             render_empty: true
    map_element "glaze", to: :glaze, render_nil: true, render_empty: true
    map_element "render_nil_nested", to: :render_nil_nested, render_nil: true,
                                     render_default: true
    map_element "dimensions", to: :dimensions, render_empty: false
  end

  yaml do
    map "name", to: :name, render_nil: true, render_empty: true
    map "clay_type", to: :clay_type, render_nil: false, render_empty: true
    map "glaze", to: :glaze, render_nil: true, render_empty: true
    map "dimensions", to: :dimensions, render_empty: false
    map "render_nil_nested", to: :render_nil_nested, render_nil: false
  end

  toml do
    map "name", to: :name, render_nil: :empty, render_empty: true
    map "clay_type", to: :clay_type, render_nil: false, render_empty: true
    map "glaze", to: :glaze, render_nil: false, render_empty: true
    map "dimensions", to: :dimensions, render_empty: false
  end
end

module RenderNilSpec
  class OmitNilModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "omit-nil-model"
      map_element "items", to: :items, render_nil: :omit
    end

    key_value do
      map "items", to: :items, render_nil: :omit
    end
  end

  class ExplicitNilModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "explicit-nil-model"
      map_element "items", to: :items, render_nil: :as_nil
    end

    yaml do
      map "items", to: :items, render_nil: :as_nil
    end
  end

  class AsBlankNilModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "omit-nil-model"
      map_element "items", to: :items, render_nil: :as_blank
    end
  end

  class AsEmptyNilModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    yaml do
      map "items", to: :items, render_nil: :as_empty
    end
  end
end

RSpec.describe RenderNil do
  let(:attributes) do
    {
      name: nil,
      clay_type: nil,
      glaze: nil,
      dimensions: nil,
      render_nil_nested: RenderNilNested.new,
    }
  end

  let(:model) { described_class.new(attributes) }

  it "serializes to JSON with render_nil option" do
    expected_json = {
      name: nil,
      clay_type: nil,
      glaze: nil,
    }.to_json

    expect(model.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with render_nil option" do
    json = attributes.to_json
    pottery = described_class.from_json(json)
    expect(pottery.name).to be_nil
    expect(pottery.clay_type).to be_nil
    expect(pottery.glaze).to be_nil
    expect(pottery.dimensions).to be_nil
  end

  it "serializes to XML with render_nil option" do
    expected_xml = <<~XML
      <render_nil>
        <name xsi:nil="true"/>
        <glaze xsi:nil="true"/>
        <render_nil_nested/>
      </render_nil>
    XML

    expect(model.to_xml).to be_xml_equivalent_to(expected_xml)
  end

  it "deserializes from XML with render_nil option" do
    xml = <<~XML
      <render_nil>
        <name xsi:nil="true" />
        <glaze xsi:nil="true" />
      </render_nil>
    XML

    pottery = described_class.from_xml(xml)
    expect(pottery.name).to be_nil
    expect(pottery.glaze).to be_nil
  end

  it "serializes to YAML with render_nil option" do
    expected_yaml = <<~YAML
      ---
      name:
      glaze:
    YAML

    generated_yaml = model.to_yaml.strip

    # Removing empty spaces from the end of the line because of and issue in
    # libyaml -> https://github.com/yaml/libyaml/issues/46
    generated_yaml = generated_yaml.gsub(": \n", ":\n")

    expect(generated_yaml).to eq(expected_yaml.strip)
  end

  it "deserializes from YAML with render_nil option" do
    yaml = <<~YAML
      ---
      glaze:
    YAML

    pottery = described_class.from_yaml(yaml)
    expect(pottery.name).to eq("Unnamed Pottery")
    expect(pottery.glaze).to be_nil
  end

  context "with empty string as values for attributes" do
    let(:attributes) do
      {
        name: "",
        clay_type: "",
        glaze: "",
        dimensions: [],
        render_nil_nested: RenderNilNested.new,
      }
    end

    it "does not treat empty string as nil" do
      expected_yaml = <<~YAML
        ---
        name: ''
        clay_type: ''
        glaze: ''
      YAML

      generated_yaml = model.to_yaml.strip

      # Removing empty spaces from the end of the line because of and issue in
      # libyaml -> https://github.com/yaml/libyaml/issues/46
      generated_yaml = generated_yaml.gsub(": \n", ":\n")

      expect(generated_yaml).to eq(expected_yaml.strip)
    end
  end

  describe "render_nil option" do
    context "when :omit" do
      let(:model) { RenderNilSpec::OmitNilModel.new(items: nil) }

      describe "YAML" do
        let(:parsed) do
          RenderNilSpec::OmitNilModel.from_yaml(yaml)
        end

        let(:yaml) do
          <<~YAML
            ---
            items:
          YAML
        end

        it "omits nil collections while deserialize" do
          expect(model.items).to be_nil
        end

        it "omits nil collections" do
          expect(parsed.to_yaml.strip).to eq("--- {}")
        end
      end

      describe "XML" do
        let(:parsed) { RenderNilSpec::OmitNilModel.from_xml(xml) }

        let(:xml) do
          <<~XML
            <omit-nil-model/>
          XML
        end

        it "omits nil collection" do
          expect(model.to_xml).not_to include("<items")
        end

        it "omits nil collections while deserialize" do
          expect(parsed.items).to be_nil
        end
      end
    end

    context "when :as_nil" do
      let(:model) { RenderNilSpec::ExplicitNilModel.new(items: nil) }

      describe "YAML" do
        let(:yaml) do
          <<~YAML
            ---
            items:
          YAML
        end

        let(:parsed) do
          RenderNilSpec::ExplicitNilModel.from_yaml(yaml)
        end

        it "renders explicit nil" do
          expect(model.to_yaml).to include("items:")
        end

        it "sets nil values while deserialize" do
          expect(parsed.items).to be_nil
        end
      end

      describe "XML" do
        let(:xml) do
          <<~XML
            <explicit-nil-model>
              <items xsi:nil="true"/>
            </explicit-nil-model>
          XML
        end

        let(:parsed) do
          RenderNilSpec::ExplicitNilModel.from_xml(xml)
        end

        it "renders explicit nil" do
          expect(model.to_xml).to include('<items xsi:nil="true"/>')
        end

        it "sets nil values while deserialize" do
          expect(parsed.items).to be_nil
        end
      end
    end

    context "when :as_blank" do
      let(:model) { RenderNilSpec::AsBlankNilModel.new(items: nil) }

      let(:parsed) do
        RenderNilSpec::AsBlankNilModel.from_xml(xml)
      end

      let(:xml) do
        <<~XML
          <explicit-nil-model>
            <items/>
          </explicit-nil-model>
        XML
      end

      it "creates blank element from nil collections" do
        expect(model.to_xml).to include("<items/>")
      end

      it "sets blank values while deserialize" do
        expect(parsed.items).to eq([])
      end
    end

    context "when :as_empty" do
      let(:model) { RenderNilSpec::AsEmptyNilModel.new(items: nil) }

      let(:parsed) do
        RenderNilSpec::AsEmptyNilModel.from_yaml(yaml)
      end

      let(:yaml) do
        <<~YAML
          ---
          items:
        YAML
      end

      it "creates key and empty collection" do
        expect(model.to_yaml).to include("items: []")
      end

      it "sets nil value while deserialize" do
        expect(parsed.items).to be_nil
      end
    end
  end
end
