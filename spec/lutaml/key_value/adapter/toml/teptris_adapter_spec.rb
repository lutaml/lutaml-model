# frozen_string_literal: true

require "spec_helper"
begin
  require "lutaml/key_value/adapter/toml/teptris_adapter"
rescue LoadError
  # teptris is not resolvable here: every example skips.
end

TEPTRIS_AVAILABLE = defined?(Teptris)

RSpec.describe(TEPTRIS_AVAILABLE ? Lutaml::KeyValue::Adapter::Toml::TeptrisAdapter : Object) do
  before { skip "teptris is not available" unless TEPTRIS_AVAILABLE }

  describe ".parse" do
    it "parses a TOML document into a hash" do
      expect(described_class.parse("name = \"John\"\nage = 30\n"))
        .to eq("name" => "John", "age" => 30)
    end

    it "parses nested tables and arrays" do
      toml = <<~TOML
        title = "cfg"
        [owner]
        name = "t"
        tags = ["a", "b"]
      TOML
      expect(described_class.parse(toml))
        .to eq("title" => "cfg", "owner" => { "name" => "t", "tags" => %w[a b] })
    end

    it "materializes dates and datetimes like tomlib" do
      require "date"
      doc = described_class.parse("d = 1979-05-27\ndt = 1979-05-27T07:32:00Z\n")
      expect(doc["d"]).to be_a(Date)
      expect(doc["dt"]).to be_a(Time)
    end

    it "reports parse errors with line and column" do
      expect { described_class.parse("a = [1,") }
        .to raise_error(Teptris::ParseError) do |e|
          expect(e.line).to eq(1)
          expect(e.column).to eq(8)
        end
    end
  end

  describe "#to_toml" do
    it "dumps a hash to TOML" do
      attributes = { "name" => "x", "nested" => { "a" => [1, 2] } }
      expect(described_class.new(attributes).to_toml)
        .to include("name", "[nested]", "a = [1, 2]")
    end

    it "unwraps the __root__ KeyValueElement wrapper" do
      element = Lutaml::KeyValue::DataModel::Element.new("__root__")
      name_child = Lutaml::KeyValue::DataModel::Element.new("name")
      name_child.value = "x"
      element.add_child(name_child)
      expect(described_class.new(element).to_toml).to include("name")
    end
  end

  it "round-trips through the model layer" do
    attributes = { "name" => "John", "age" => 30 }
    adapter_toml = described_class.new(attributes).to_toml
    expect(described_class.parse(adapter_toml)).to eq(attributes)
  end
end
