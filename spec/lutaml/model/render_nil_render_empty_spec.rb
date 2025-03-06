module RenderNilClasses
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

module RenderEmptyClasses
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

RSpec.describe "Collection States and Rendering" do
  describe "Collection States" do
    context "with default behavior (initialize_empty: false)" do
      it "defaults to nil" do
        model = RenderNilClasses::DefaultModel.new
        expect(model.items).to be_nil
        expect(model.to_xml).to eq("<default-model/>")
      end
    end

    context "with initialize_empty: true" do
      it "defaults to empty array" do
        model = RenderNilClasses::EmptyInitModel.new
        expect(model.items).to eq([])
        expect(model.to_xml).to eq("<empty-init-model/>")
      end
    end
  end

  describe "Rendering Behaviors" do
    context "render_nil options" do
      context "with :omit" do
        it "omits nil collections" do
          model = RenderNilClasses::OmitNilModel.new

          xml = model.to_xml
          expect(xml).not_to include("<items")

          yaml = model.to_yaml
          expect(yaml.strip).to eq("--- {}")
        end

        it "omits nil collections while deserialize" do
          xml = <<~XML
            <omit-nil-model/>
          XML
          model = RenderNilClasses::OmitNilModel.from_xml(xml)
          expect(model.items).to be_nil

          yaml = <<~YAML
            ---
            items:
          YAML
          model = RenderNilClasses::OmitNilModel.from_yaml(yaml)
          expect(model.items).to be_nil
        end
      end

      context "with :as_nil" do
        it "renders explicit nil" do
          model = RenderNilClasses::ExplicitNilModel.new

          xml = model.to_xml
          expect(xml).to include('<items xsi:nil="true"/>')

          yaml = model.to_yaml
          expect(yaml).to include("items:")
        end

        it "sets nil values while deserialize" do
          xml = <<~XML
            <explicit-nil-model>
              <items xsi:nil="true"/>
            </explicit-nil-model>
          XML
          model = RenderNilClasses::ExplicitNilModel.from_xml(xml)
          expect(model.items).to be_nil

          yaml = <<~YAML
            ---
            items:
          YAML
          model = RenderNilClasses::ExplicitNilModel.from_yaml(yaml)
          expect(model.items).to be_nil
        end
      end

      context "with :as_blank" do
        it "creates blank element from nil collections" do
          model = RenderNilClasses::AsBlankNilModel.new

          xml = model.to_xml
          expect(xml).to include("<items/>")
        end

        it "sets blank values while deserialize" do
          xml = <<~XML
            <explicit-nil-model>
              <items/>
            </explicit-nil-model>
          XML
          model = RenderNilClasses::AsBlankNilModel.from_xml(xml)
          expect(model.items).to eq([])
        end
      end

      context "with :as_empty" do
        it "creates key and empty collection" do
          model = RenderNilClasses::AsEmptyNilModel.new

          yaml = model.to_yaml
          expect(yaml).to include("items: []")
        end

        it "sets empty values while deserialize" do
          yaml = <<~YAML
            ---
            items:
          YAML
          model = RenderNilClasses::AsEmptyNilModel.from_yaml(yaml)
          expect(model.items).to eq([])
        end
      end
    end

    context "render_empty options" do
      context "with :omit" do
        it "omits empty collections" do
          model = RenderEmptyClasses::OmitEmptyModel.new(items: [])

          xml = model.to_xml
          expect(xml).not_to include("<items")

          yaml = model.to_yaml
          expect(yaml.strip).to eq("--- {}")
        end
      end

      context "with :as_empty" do
        it "renders explicit empty collection" do
          model = RenderEmptyClasses::ExplicitEmptyModel.new(items: [])

          yaml = model.to_yaml
          expect(yaml).to include("items: []")
        end

        it "sets empty values while deserialize" do
          yaml = <<~YAML
            ---
            items: []
          YAML
          model = RenderEmptyClasses::ExplicitEmptyModel.from_yaml(yaml)
          expect(model.items).to eq([])
        end
      end

      context "with :as_blank" do
        it "creates blank element from empty collections" do
          model = RenderEmptyClasses::ExplicitBlankModel.new(items: [])

          xml = model.to_xml
          expect(xml).to include("<items/>")
        end

        it "sets blank values while deserialize" do
          xml = <<~XML
            <explicit-blank-model>
              <items/>
            </explicit-blank-model>
          XML
          model = RenderEmptyClasses::ExplicitBlankModel.from_xml(xml)
          expect(model.items).to eq([])
        end
      end

      context "with :as_nil" do
        it "renders explicit nil" do
          model = RenderEmptyClasses::ExplicitNilModel.new(items: [])

          xml = model.to_xml
          expect(xml).to include('<items xsi:nil="true"/>')

          yaml = model.to_yaml
          expect(yaml).to include("items:")
        end

        it "sets nil values while deserialize" do
          xml = <<~XML
            <explicit-nil-model>
              <items xsi:nil="true"/>
            </explicit-nil-model>
          XML
          model = RenderEmptyClasses::ExplicitNilModel.from_xml(xml)
          expect(model.items).to eq([])

          yaml = <<~YAML
            ---
            items: []
          YAML
          model = RenderEmptyClasses::ExplicitNilModel.from_yaml(yaml)
          expect(model.items).to eq([])
        end
      end
    end
  end
end
