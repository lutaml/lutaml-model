require "spec_helper"

RSpec.describe "Collection attribute mutations" do
  describe "serialization after mutation" do
    let(:namespace_class) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/test"
        prefix_default "t"
      end
    end

    let(:item_class) do
      ns = namespace_class
      Class.new(Lutaml::Model::Serializable) do
        xml do
          element "item"
          namespace ns
          map_attribute "value", to: :value
        end

        attribute :value, :string
      end
    end

    let(:container_class) do
      ns = namespace_class
      item = item_class
      Class.new(Lutaml::Model::Serializable) do
        xml do
          element "container"
          namespace ns
          map_element "item", to: :items
        end

        attribute :items, item, collection: true, default: -> { [] }

        def add_item(value)
          items << self.class.attributes[:items].type.new(value: value)
        end
      end
    end

    context "when collection is empty with default value" do
      it "does not serialize empty collection" do
        container = container_class.new
        xml = container.to_xml

        expect(xml).not_to include("<item")
        expect(xml).to include("<container")
      end
    end

    context "when collection is mutated with <<" do
      it "serializes the mutated collection" do
        container = container_class.new
        container.items << item_class.new(value: "one")
        xml = container.to_xml

        expect(xml).to include('<item')
        expect(xml).to include('value="one"')
      end
    end

    context "when collection is mutated via custom method" do
      it "serializes the mutated collection" do
        container = container_class.new
        container.add_item("two")
        xml = container.to_xml

        expect(xml).to include('<item')
        expect(xml).to include('value="two"')
      end
    end

    context "when collection is set via constructor" do
      it "serializes the collection" do
        container = container_class.new(items: [item_class.new(value: "three")])
        xml = container.to_xml

        expect(xml).to include('<item')
        expect(xml).to include('value="three"')
      end
    end

    context "when collection has multiple mutations" do
      it "serializes all items" do
        container = container_class.new
        container.items << item_class.new(value: "four")
        container.add_item("five")
        container.items << item_class.new(value: "six")
        xml = container.to_xml

        expect(xml.scan(/<item/).size).to eq(3)
        expect(xml).to include('value="four"')
        expect(xml).to include('value="five"')
        expect(xml).to include('value="six"')
      end
    end

    context "scalar default values (regression test)" do
      let(:defaults_class) do
        Class.new(Lutaml::Model::Serializable) do
          xml do
            element "with-defaults"
            map_element "name", to: :name
            map_element "count", to: :count
          end

          attribute :name, :string, default: -> { "default-name" }
          attribute :count, :integer, default: -> { 0 }
        end
      end

      it "does not serialize scalar default values" do
        instance = defaults_class.new
        xml = instance.to_xml

        expect(xml).not_to include("<name>")
        expect(xml).not_to include("<count>")
        expect(xml).to include("<with-defaults")
      end
    end
  end
end
