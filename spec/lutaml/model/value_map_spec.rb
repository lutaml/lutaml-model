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
      map_element "omitted_as_omitted", to: :omitted_as_omitted, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :omitted },
      }
      map_element "omitted_as_nil", to: :omitted_as_nil, value_map: {
        from: { omitted: :nil },
        to: { nil: :omitted },
      }
      map_element "omitted_as_empty", to: :omitted_as_empty, value_map: {
        from: { omitted: :empty },
        to: { empty: :omitted },
      }

      map_element "nil_as_nil", to: :nil_as_nil, value_map: {
        from: { nil: :nil },
        to: { nil: :nil },
      }
      map_element "nil_as_omitted", to: :nil_as_omitted, value_map: {
        from: { nil: :omitted },
        to: { omitted: :nil },
      }
      map_element "nil_as_empty", to: :nil_as_empty, value_map: {
        from: { nil: :empty },
        to: { empty: :nil },
      }

      map_element "empty_as_empty", to: :empty_as_empty, value_map: {
        from: { empty: :empty },
        to: { empty: :empty },
      }
      map_element "empty_as_nil", to: :empty_as_nil, value_map: {
        from: { empty: :nil },
        to: { nil: :empty },
      }
      map_element "empty_as_omitted", to: :empty_as_omitted, value_map: {
        from: { empty: :omitted },
        to: { omitted: :empty },
      }
    end

    key_value do
      map "omitted_as_omitted", to: :omitted_as_omitted, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :omitted },
      }
      map "omitted_as_nil", to: :omitted_as_nil, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :nil, nil: :omitted },
      }
      map "omitted_as_empty", to: :omitted_as_empty, value_map: {
        from: { omitted: :omitted },
        to: { omitted: :empty, empty: :omitted },
      }

      map "nil_as_nil", to: :nil_as_nil, value_map: {
        from: { nil: :nil },
        to: { nil: :nil },
      }
      map "nil_as_omitted", to: :nil_as_omitted, value_map: {
        from: { nil: :nil },
        to: { nil: :omitted, omitted: :nil },
      }
      map "nil_as_empty", to: :nil_as_empty, value_map: {
        from: { nil: :nil },
        to: { nil: :empty, empty: :nil },
      }

      map "empty_as_empty", to: :empty_as_empty, value_map: {
        from: { empty: :empty },
        to: { empty: :empty },
      }
      map "empty_as_nil", to: :empty_as_nil, value_map: {
        from: { empty: :empty },
        to: { empty: :nil, nil: :empty },
      }
      map "empty_as_omitted", to: :empty_as_omitted, value_map: {
        from: { empty: :empty },
        to: { empty: :omitted, omitted: :empty },
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

    # it "round trips correctly" do
    #   expect(parsed.to_yaml).to eq(yaml)
    # end
  end

  # describe "XML" do
  #   let(:xml) do
  #     <<~XML
  #       <WithValueMaps>
  #         <nilAsNil xsi:nil="true"></nilAsNil>
  #         <nilAsOmitted xsi:nil="true"></nilAsOmitted>
  #         <nilAsEmpty xsi:nil="true"></nilAsEmpty>
  #         <emptyAsEmpty/>
  #         <emptyAsNil/>
  #         <emptyAsOmitted/>
  #       </WithValueMaps>
  #     XML
  #   end
  # end
end
