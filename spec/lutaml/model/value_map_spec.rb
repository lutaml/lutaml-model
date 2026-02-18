# map :x, to: :y, value_map: {
#   from_xml: {omitted: :omitted, xsi_nil: nil, empty: [] },
#   to_xml: {omitted: :omitted, nil: :nil, empty: :empty}
# }

module ValueMapSpec
  class WithValueMaps < Lutaml::Model::Serializable
    attribute :omitted_as_omitted, :string
    attribute :omitted_as_nil, :string
    attribute :omitted_as_empty, :string

    attribute :nil_as_nil, :string
    attribute :nil_as_omitted, :string
    attribute :nil_as_empty, :string

    attribute :empty_as_empty, :string
    attribute :empty_as_nil, :string
    attribute :empty_as_omitted, :string

    xml do
      element "WithValueMaps"

      map_element "omittedAsOmitted", to: :omitted_as_omitted, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :omitted },
      }
      map_element "omittedAsNil", to: :omitted_as_nil, value_map: {
        from: { omitted: :nil },
        to: { omitted: :nil },
      }
      map_element "omittedAsEmpty", to: :omitted_as_empty, value_map: {
        from: { omitted: :empty },
        to: { omitted: :empty },
      }

      map_element "nilAsNil", to: :nil_as_nil, value_map: {
        from: { nil: :nil },
        to: { nil: :nil },
      }
      map_element "nilAsOmitted", to: :nil_as_omitted, value_map: {
        from: { nil: :omitted },
        to: { nil: :omitted },
      }
      map_element "nilAsEmpty", to: :nil_as_empty, value_map: {
        from: { nil: :empty },
        to: { nil: :empty },
      }

      map_element "emptyAsEmpty", to: :empty_as_empty, value_map: {
        from: { empty: :empty },
        to: { empty: :empty },
      }
      map_element "emptyAsNil", to: :empty_as_nil, value_map: {
        from: { empty: :nil },
        to: { empty: :nil },
      }
      map_element "emptyAsOmitted", to: :empty_as_omitted, value_map: {
        from: { empty: :omitted },
        to: { empty: :omitted },
      }
    end

    key_value do
      map "omitted_as_omitted", to: :omitted_as_omitted, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :omitted },
      }
      map "omitted_as_nil", to: :omitted_as_nil, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :nil },
      }
      map "omitted_as_empty", to: :omitted_as_empty, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :empty },
      }

      map "nil_as_nil", to: :nil_as_nil, value_map: {
        from: { nil: :nil },
        to: { nil: :nil },
      }
      map "nil_as_omitted", to: :nil_as_omitted, value_map: {
        from: { nil: :nil },
        to: { nil: :omitted },
      }
      map "nil_as_empty", to: :nil_as_empty, value_map: {
        from: { nil: :nil },
        to: { nil: :empty },
      }

      map "empty_as_empty", to: :empty_as_empty, value_map: {
        from: { empty: :empty },
        to: { empty: :empty },
      }
      map "empty_as_nil", to: :empty_as_nil, value_map: {
        from: { empty: :empty },
        to: { empty: :nil },
      }
      map "empty_as_omitted", to: :empty_as_omitted, value_map: {
        from: { empty: :empty },
        to: { empty: :omitted },
      }
    end
  end
end

RSpec.describe "ValueMap" do
  describe "YAML" do
    let(:model) do
      uninitialized = Lutaml::Model::UninitializedClass.instance

      ValueMapSpec::WithValueMaps.new(
        omitted_as_omitted: uninitialized,
        omitted_as_nil: uninitialized,
        omitted_as_empty: uninitialized,
        nil_as_nil: nil,
        nil_as_omitted: nil,
        nil_as_empty: nil,
        empty_as_empty: "",
        empty_as_nil: "",
        empty_as_omitted: "",
      )
    end

    let(:parsed) { ValueMapSpec::WithValueMaps.from_yaml(yaml) }

    let(:expected_yaml) do
      <<~YAML
        ---
        omitted_as_nil:
        omitted_as_empty: ''
        nil_as_nil:
        nil_as_empty: ''
        empty_as_empty: ''
        empty_as_nil:
      YAML
    end

    let(:yaml) do
      <<~YAML
        ---
        nil_as_nil:
        nil_as_omitted:
        nil_as_empty:
        empty_as_empty: ''
        empty_as_nil: ''
        empty_as_omitted: ''
      YAML
    end

    it "serializes correctly" do
      expect(parsed.to_yaml).to eq(expected_yaml)
    end

    it "deserializes correctly" do
      expected = ValueMapSpec::WithValueMaps.new(
        {
          nil_as_nil: nil,
          nil_as_omitted: nil,
          nil_as_empty: nil,
          empty_as_empty: "",
          empty_as_nil: "",
          empty_as_omitted: "",
        },
        { omitted: :omitted },
      )

      expect(parsed).to eq(expected)
    end
  end

  describe "XML" do
    context "when serializing" do
      let(:model) do
        ValueMapSpec::WithValueMaps.new(
          {
            nil_as_nil: nil,
            nil_as_omitted: nil,
            nil_as_empty: nil,
            empty_as_empty: "",
            empty_as_nil: "",
            empty_as_omitted: "",
          },
          { omitted: :omitted },
        )
      end

      let(:expected_xml) do
        <<~XML.strip
          <WithValueMaps>
            <omittedAsNil xsi:nil="true"/>
            <omittedAsEmpty/>
            <nilAsNil xsi:nil="true"/>
            <nilAsEmpty/>
            <emptyAsEmpty/>
            <emptyAsNil xsi:nil="true"/>
          </WithValueMaps>
        XML
      end

      it "sets correct values when serializing" do
        expect(model.to_xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "when deserializing" do
      let(:xml) do
        <<~XML
          <WithValueMaps>
            <nilAsNil xsi:nil="true" />
            <nilAsOmitted xsi:nil="true" />
            <nilAsEmpty xsi:nil="true" />
            <emptyAsEmpty/>
            <emptyAsNil/>
            <emptyAsOmitted/>
          </WithValueMaps>
        XML
      end

      let(:parsed) { ValueMapSpec::WithValueMaps.from_xml(xml) }

      let(:expected) do
        ValueMapSpec::WithValueMaps.new(
          {
            nil_as_nil: nil,
            nil_as_empty: "",
            empty_as_empty: "",
            empty_as_nil: nil,
            omitted_as_nil: nil,
            omitted_as_empty: "",
          },
          { omitted: :omitted },
        )
      end

      it "sets correct values when deserializing" do
        expect(parsed).to eq(expected)
      end
    end
  end
end
