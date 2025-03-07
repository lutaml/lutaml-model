module RenderEmptySpec
  class DefaultModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "default-model"
      map_element "items", to: :items
    end
  end

  class EmptyInitModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true, initialize_empty: true

    xml do
      root "empty-init-model"
      map_element "items", to: :items
    end
  end

  class OmitEmptyModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "omit-empty-model"
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
      map_element "items", to: :items, render_empty: :as_blank
    end
  end

  class ExplicitNilModel < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "explicit-nil-model"
      map_element "items", to: :items, render_empty: :as_nil
    end

    yaml do
      map "items", to: :items, render_empty: :as_nil
    end
  end
end

RSpec.describe "RenderEmptySpec" do
  describe "Collection States" do
    context "with default behavior (initialize_empty: false)" do
      it "defaults to nil" do
        model = RenderEmptySpec::DefaultModel.new
        expect(model.items).to be_nil
        expect(model.to_xml).to eq("<default-model/>")
      end
    end

    context "with initialize_empty: true" do
      it "defaults to empty array" do
        model = RenderEmptySpec::EmptyInitModel.new
        expect(model.items).to eq([])
        expect(model.to_xml).to eq("<empty-init-model/>")
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
  end
end
