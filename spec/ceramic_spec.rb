require "spec_helper"
require_relative "fixtures/ceramic"

RSpec.describe Ceramic do
  let(:xml) do
    <<~XML
      <ceramic kilnFiringTimeAttribute="2012-04-07T01:51:37.112+02:00">
        <kilnFiringTime>2012-04-07T01:51:37.112+02:00</kilnFiringTime>
      </ceramic>
    XML
  end

  it "deserializes from XML with high-precision date-time" do
    ceramic = described_class.from_xml(xml)
    expect(ceramic.kiln_firing_time.strftime("%Y-%m-%dT%H:%M:%S.%L%:z")).to eq("2012-04-07T01:51:37.112+02:00")
  end

  it "serializes to XML with high-precision date-time" do
    ceramic = described_class.from_xml(xml)
    expect(ceramic.to_xml).to be_xml_equivalent_to(xml)
  end

  it "deserializes from JSON with high-precision date-time" do
    json = {
      kilnFiringTime: "2012-04-07T01:51:37+02:00",
    }.to_json

    ceramic_from_json = described_class.from_json(json)
    expect(ceramic_from_json.kiln_firing_time).to eq(DateTime.new(2012, 4, 7,
                                                                  1, 51, 37, "+02:00"))
  end

  it "serializes to JSON with high-precision date-time" do
    ceramic = described_class.from_xml(xml)
    expected_json = {
      kilnFiringTime: "2012-04-07T01:51:37+02:00",
      kilnFiringTimeAttribute: "2012-04-07T01:51:37+02:00",
    }.to_json

    expect(ceramic.to_json).to eq(expected_json)
  end

  it "preserves milliseconds when serializing already-wrapped HighPrecisionDateTime" do
    # Create instance with an already-wrapped HighPrecisionDateTime (not from deserialization)
    high_precision_time = HighPrecisionDateTime.new(
      DateTime.new(2012, 4, 7, 1, 51, 37.112, "+02:00"),
    )
    ceramic = described_class.new
    ceramic.kiln_firing_time = high_precision_time

    # serialize_custom_value should NOT re-wrap; it should preserve the milliseconds
    result = ceramic.to_xml
    expect(result).to include(".112")
    # Verify the element contains milliseconds, not zeros
    expect(result).not_to include("01:51:37.000")
  end
end
