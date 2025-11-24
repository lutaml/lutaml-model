require "spec_helper"
require "lutaml/model"

RSpec.describe "XML ordered method" do
  context "when using ordered method for order preservation" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :car, :string, collection: true
        attribute :boat, :string, collection: true

        xml do
          element "transportation"
          ordered  # Preserve element order without validation

          map_element "car", to: :car
          map_element "boat", to: :boat
        end
      end
    end

    let(:xml_with_mixed_order) do
      <<~XML
        <transportation>
          <car>First</car>
          <boat>Second</boat>
          <car>Third</car>
        </transportation>
      XML
    end

    it "preserves element order during round-trip" do
      instance = model_class.from_xml(xml_with_mixed_order)
      
      expect(instance.car).to eq(["First", "Third"])
      expect(instance.boat).to eq(["Second"])
      
      # Round-trip should preserve order
      output_xml = instance.to_xml
      expect(output_xml).to include("<car>First</car>")
      expect(output_xml).to include("<boat>Second</boat>")
      expect(output_xml).to include("<car>Third</car>")
      
      # Verify order is preserved
      car_first_pos = output_xml.index("<car>First</car>")
      boat_pos = output_xml.index("<boat>Second</boat>")
      car_third_pos = output_xml.index("<car>Third</car>")
      
      expect(car_first_pos).to be < boat_pos
      expect(boat_pos).to be < car_third_pos
    end

    it "sets ordered flag to true" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.ordered?).to be true
    end
  end

  context "when not using ordered" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :car, :string, collection: true
        attribute :boat, :string, collection: true

        xml do
          element "transportation"
          # No ordered method called

          map_element "car", to: :car
          map_element "boat", to: :boat
        end
      end
    end

    let(:xml_with_mixed_order) do
      <<~XML
        <transportation>
          <car>First</car>
          <boat>Second</boat>
          <car>Third</car>
        </transportation>
      XML
    end

    it "outputs elements in attribute declaration order" do
      instance = model_class.from_xml(xml_with_mixed_order)
      
      output_xml = instance.to_xml
      
      # All cars should come before boats (attribute declaration order)
      all_car_indices = []
      all_boat_indices = []
      
      output_xml.scan(/<car>.*?<\/car>/) do
        all_car_indices << Regexp.last_match.begin(0)
      end
      
      output_xml.scan(/<boat>.*?<\/boat>/) do
        all_boat_indices << Regexp.last_match.begin(0)
      end
      
      expect(all_car_indices.max).to be < all_boat_indices.min if all_car_indices.any? && all_boat_indices.any?
    end

    it "sets ordered flag to false" do
      mapping = model_class.mappings_for(:xml)
      expect(mapping.ordered?).to be_falsey
    end
  end
end
