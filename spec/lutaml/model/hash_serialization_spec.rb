require "spec_helper"
require "lutaml/model"

module HashSerialization
  class TempRange < Lutaml::Model::Serializable
    attribute :min, :integer
    attribute :max, :integer
  end

  class Klin < Lutaml::Model::Serializable
    attribute :location, :string
    attribute :temperature_range, TempRange
  end

  class Ceramic < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :klin, Klin

    hash do
      map :type, to: :type
      map :klin, to: :klin
    end
  end
end

RSpec.describe "HashSerialization" do
  let(:hash) do
    {
      "type" => "vase",
      "klin" => {
        "location" => "paris",
        "temperature_range" => {
          "min" => 50,
          "max" => 1300,
        },
      },
    }
  end

  it "from_hash" do
    instance = HashSerialization::Ceramic.from_hash(hash)

    expect(instance.type).to eq("vase")
    expect(instance.klin.location).to eq("paris")
    expect(instance.klin.temperature_range.min).to eq(50)
    expect(instance.klin.temperature_range.max).to eq(1300)
  end

  it "to_hash" do
    instance = HashSerialization::Ceramic.from_hash(hash)
    serialized = instance.to_hash

    expect(serialized).to eq(hash)
  end
end
