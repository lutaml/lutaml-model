module RenderEmptySpec
  class DefaultModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      element "default-model"
      map_element "items", to: :items
    end
  end

  class EmptyInitModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true, initialize_empty: true

    xml do
      element "empty-init-model"
      map_element "items", to: :items
    end
  end

  class OmitEmptyModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      element "omit-empty-model"
      map_element "items", to: :items, render_empty: :omit
    end

    key_value do
      map "items", to: :items, render_empty: :omit
    end
  end

  class ExplicitEmptyModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    key_value do
      map "items", to: :items, render_empty: :as_empty
    end
  end

  class ExplicitBlankModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      element "explicit-blank-model"
      map_element "items", to: :items, render_empty: :as_blank
    end
  end

  class ExplicitNilModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      element "explicit-nil-model"
      map_element "items", to: :items, render_empty: :as_nil
    end

    yaml do
      map "items", to: :items, render_empty: :as_nil
    end
  end

  # Model with ordered mapping to test element_order serialization path
  class ExplicitBlankOrderedModel < Lutaml::Model::Serializable
    attribute :authority, :string
    attribute :topic, :string, collection: true

    xml do
      element "subject"
      ordered
      map_element "topic", to: :topic, render_empty: :as_blank
    end
  end

  # Model using value_map to override render_empty default
  # Regression: user-provided value_map entries must take precedence over
  # computed defaults from render_nil/render_empty DSL options.
  class ValueMapEmptyModel < Lutaml::Model::Serializable
    attribute :code, :string
    attribute :page, :string

    xml do
      root "doc"
      map_attribute "code", to: :code
      map_attribute "page", to: :page,
                            value_map: { to: { empty: :empty } }
    end
  end

  # Model for testing empty attribute round-trip preservation
  class ImageModel < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :alt, :string
    attribute :src, :string

    xml do
      element "image"
      map_attribute "id", to: :id
      map_attribute "alt", to: :alt, render_empty: true
      map_attribute "src", to: :src
    end
  end

  # Model with ordered mapping to test element_order with :as_nil
  class ExplicitNilOrderedModel < Lutaml::Model::Serializable
    attribute :authority, :string
    attribute :topic, :string, collection: true

    xml do
      element "subject"
      ordered
      map_element "topic", to: :topic, render_empty: :as_nil
    end
  end
end

RSpec.describe "RenderEmptySpec" do
  describe "Collection States" do
    context "with default behavior (initialize_empty: false)" do
      it "defaults to nil" do
        model = RenderEmptySpec::DefaultModel.new
        expect(model.items).to be_nil
        expect(model.to_xml).to be_xml_equivalent_to("<default-model/>")
      end
    end

    context "with initialize_empty: true" do
      it "defaults to empty array" do
        model = RenderEmptySpec::EmptyInitModel.new
        expect(model.items).to eq([])
        expect(model.to_xml).to be_xml_equivalent_to("<empty-init-model/>")
      end
    end
  end

  describe "render_empty option" do
    context "when :omit" do
      let(:model) do
        RenderEmptySpec::OmitEmptyModel.new(items: [])
      end

      it "omits empty collections in XML" do
        expect(model.to_xml).not_to include("<items")
      end

      it "omits empty collections in YAML" do
        expect(model.to_yaml.strip).to eq("--- {}")
      end
    end

    context "when :as_empty" do
      let(:model) do
        RenderEmptySpec::ExplicitEmptyModel.new(items: [])
      end

      let(:parsed) do
        RenderEmptySpec::ExplicitEmptyModel.from_yaml(yaml)
      end

      let(:yaml) do
        <<~YAML
          ---
          items: []
        YAML
      end

      it "renders explicit empty collection" do
        expect(model.to_yaml).to eq(yaml)
      end

      it "sets empty values while deserialize" do
        expect(parsed.items).to eq([])
      end
    end

    context "when :as_blank" do
      let(:model) do
        RenderEmptySpec::ExplicitBlankModel.new(items: [])
      end

      let(:parsed) do
        RenderEmptySpec::ExplicitBlankModel.from_xml(xml)
      end

      let(:xml) do
        <<~XML
          <explicit-blank-model>
            <items/>
          </explicit-blank-model>
        XML
      end

      it "creates blank element from empty collections" do
        expect(model.to_xml).to include("<items/>")
      end

      it "sets blank values while deserialize" do
        expect(parsed.items).to eq([])
      end
    end

    context "when :as_nil" do
      let(:model) do
        RenderEmptySpec::ExplicitNilModel.new(items: [])
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
          RenderEmptySpec::ExplicitNilModel.from_xml(xml)
        end

        it "renders explicit nil" do
          expect(model.to_xml).to include('<items xsi:nil="true"/>')
        end

        it "sets nil values while deserializing" do
          expect(parsed.items).to eq([])
        end
      end

      describe "YAML" do
        let(:yaml) do
          <<~YAML
            ---
            items: []
          YAML
        end

        it "renders explicit nil in YAML" do
          expect(model.to_yaml).to include("items:")
        end

        it "sets nil values while deserializing YAML" do
          model = RenderEmptySpec::ExplicitNilModel.from_yaml(yaml)
          expect(model.items).to eq([])
        end
      end
    end

    context "when :as_blank with ordered mapping (element_order path)" do
      it "renders empty collection as blank element on parsed model with element_order" do
        xml = '<subject authority="lcsh"><topic/></subject>'
        parsed = RenderEmptySpec::ExplicitBlankOrderedModel.from_xml(xml)
        # Verify element_order is set (meaning ordered path will be used)
        expect(parsed.respond_to?(:element_order)).to be true
        expect(parsed.to_xml).to include("<topic/>")
      end
    end

    context "when :as_nil with ordered mapping (element_order path)" do
      it "renders empty collection as nil element on parsed model with element_order" do
        xml = '<subject authority="lcsh"><topic xsi:nil="true"/></subject>'
        parsed = RenderEmptySpec::ExplicitNilOrderedModel.from_xml(xml)
        # Verify element_order is set (meaning ordered path will be used)
        expect(parsed.respond_to?(:element_order)).to be true
        expect(parsed.to_xml).to include('<topic xsi:nil="true"/>')
      end
    end
  end

  describe "Empty attribute round-trip preservation" do
    context "when an XML attribute is explicitly set to empty string" do
      let(:xml) do
        '<image alt="" id="img1" src="photo.png"/>'
      end

      it "preserves empty attribute value after round-trip" do
        parsed = RenderEmptySpec::ImageModel.from_xml(xml)
        expect(parsed.alt).to eq("")
        roundtripped = parsed.to_xml
        expect(roundtripped).to include('alt=""')
      end
    end

    context "when an XML attribute is not present" do
      let(:xml) do
        '<image id="img1" src="photo.png"/>'
      end

      it "does not render the missing attribute" do
        parsed = RenderEmptySpec::ImageModel.from_xml(xml)
        expect(parsed.alt).to be_nil
        roundtripped = parsed.to_xml
        expect(roundtripped).not_to include("alt")
      end
    end

    context "when programmatically setting an attribute to empty string" do
      let(:model) do
        RenderEmptySpec::ImageModel.new(id: "img1", alt: "", src: "photo.png")
      end

      it "renders the empty attribute" do
        expect(model.to_xml).to include('alt=""')
      end
    end
  end

  describe "value_map precedence over render_empty defaults" do
    # Regression: value_map: { to: { empty: :empty } } must override the
    # computed default from render_empty: false (which maps empty → :omitted).
    # Bug was Hash#merge order: defaults merged ON TOP of user entries.
    context "with value_map to: { empty: :empty } on XML attribute" do
      it "round-trips empty string attribute via value_map" do
        xml = '<doc code="A1" page=""/>'
        parsed = RenderEmptySpec::ValueMapEmptyModel.from_xml(xml)
        expect(parsed.page).to eq("")
        roundtripped = parsed.to_xml
        expect(roundtripped).to include('page=""')
      end

      it "round-trips empty string set programmatically" do
        model = RenderEmptySpec::ValueMapEmptyModel.new(code: "B2", page: "")
        expect(model.to_xml).to include('page=""')
      end

      it "omits attribute when value is nil (no value_map override for nil)" do
        model = RenderEmptySpec::ValueMapEmptyModel.new(code: "C3", page: nil)
        expect(model.to_xml).not_to include("page")
      end
    end
  end
end
