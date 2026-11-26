# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::ModelCompiler do
  let(:compiler) { described_class.new }
  let(:model_input) do
    <<~LML
      models T {
        enum Color {
          red {
            description "Red color"
          }
          blue {
            description "Blue color"
          }
        }
        class Item {
          attribute color {
            type Color
            cardinality 1
          }
        }
      }
    LML
  end
  let(:compiled) do
    require "tempfile"
    file = Tempfile.new(["m", ".lml"])
    file.write(model_input)
    file.rewind
    compiler.compile(file)
  ensure
    file.close!
  end

  it "exposes enum value names and descriptions" do
    color = compiled["Color"]
    expect(color.values.map(&:name)).to eq %w[red blue]
    expect(color.values.map(&:description)).to eq ["Red color", "Blue color"]
  end

  it "builds enum instances carrying descriptions" do
    color = compiled["Color"]
    red = color.red
    expect(red.value).to eq "red"
    expect(red.description).to eq "Red color"
  end

  it "hydrates enum-typed attributes from bare and qualified values" do
    compiled
    data = Tempfile.new(["d", ".lml"])
    data.write(<<~LML)
      instance X {
        isa Item
        color = Color::red
      }
    LML
    data.rewind
    item = compiler.hydrate(data)
    expect(item.color).to be_a(compiled["Color"])
    expect(item.color.value).to eq "red"
    expect(item.color.description).to eq "Red color"
  ensure
    data.close!
  end

  it "validates instances referencing qualified model types" do
    compiler.compile(File.open("spec/lml/fixtures/lml/iho_s102_check.lml"))
    errors = compiler.validate(
      File.open("spec/lml/fixtures/lml/data_s102_check.lml"),
      compiled: compiler.compiled_classes,
    )
    expect(errors).to be_empty
  end
end
