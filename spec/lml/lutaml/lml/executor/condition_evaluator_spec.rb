# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"
require "lutaml/lml/executor"

RSpec.describe Lutaml::Lml::Executor::ConditionEvaluator do
  let(:item_class) { Struct.new(:id) }

  describe ".evaluate" do
    it "passes when count >= N is satisfied" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count >= 2"],
      )
      instances = [item_class.new(1), item_class.new(2)]
      errors = described_class.evaluate(collection, instances)
      expect(errors).to eq([])
    end

    it "fails when count >= N is not satisfied" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count >= 5"],
      )
      instances = [item_class.new(1), item_class.new(2)]
      errors = described_class.evaluate(collection, instances)
      expect(errors.length).to eq(1)
      expect(errors.first).to include("count >= 5")
      expect(errors.first).to include("got 2")
    end

    it "passes when count == N" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count == 3"],
      )
      instances = [item_class.new(1), item_class.new(2), item_class.new(3)]
      errors = described_class.evaluate(collection, instances)
      expect(errors).to eq([])
    end

    it "passes when count <= N" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count <= 10"],
      )
      instances = [item_class.new(1), item_class.new(2)]
      errors = described_class.evaluate(collection, instances)
      expect(errors).to eq([])
    end

    it "returns empty array when no validations" do
      collection = Lutaml::Lml::Collection.new(name: "test")
      errors = described_class.evaluate(collection, [])
      expect(errors).to eq([])
    end

    it "raises for unsupported condition forms" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["unknown_thing"],
      )
      errors = described_class.evaluate(collection, [])
      expect(errors.length).to eq(1)
      expect(errors.first).to include("Unsupported condition")
    end
  end

  describe "block conditions (all?/any?)" do
    let(:item_class) { Struct.new(:name, :components) }

    it "passes when all instances satisfy the predicate" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.components.count > 0 }"],
      )
      instances = [
        item_class.new("A", [1]),
        item_class.new("B", [1, 2]),
      ]
      errors = described_class.evaluate(collection, instances)
      expect(errors).to eq([])
    end

    it "fails when any instance does not satisfy the predicate" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.components.count > 0 }"],
      )
      instances = [
        item_class.new("A", [1]),
        item_class.new("B", []),
      ]
      errors = described_class.evaluate(collection, instances)
      expect(errors.length).to eq(1)
      expect(errors.first).to include("failed for at least one instance")
    end

    it "passes any? when at least one instance matches" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ['any? { |i| i.name == "B" }'],
      )
      instances = [
        item_class.new("A", [1]),
        item_class.new("B", [2]),
      ]
      errors = described_class.evaluate(collection, instances)
      expect(errors).to eq([])
    end

    it "fails any? when no instances match" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ['any? { |i| i.name == "Z" }'],
      )
      instances = [item_class.new("A", [1]), item_class.new("B", [2])]
      errors = described_class.evaluate(collection, instances)
      expect(errors.length).to eq(1)
    end

    it "supports numeric, string, boolean, and nil literals" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: [
          "all? { |i| i.components.count >= 1 }",
          'all? { |i| i.name != "X" }',
        ],
      )
      instances = [item_class.new("A", [1])]
      errors = described_class.evaluate(collection, instances)
      expect(errors).to eq([])
    end

    it "reports malformed block conditions" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { we fubar }"],
      )
      errors = described_class.evaluate(collection, [])
      expect(errors.length).to eq(1)
      expect(errors.first).to include("Invalid block condition")
    end
  end

  describe "count comparison operators" do
    it "passes when count > N is strictly satisfied" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count > 2"],
      )
      instances = [item_class.new(1), item_class.new(2), item_class.new(3)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "fails when count > N is only equal" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count > 2"],
      )
      instances = [item_class.new(1), item_class.new(2)]
      errors = described_class.evaluate(collection, instances)
      expect(errors.length).to eq(1)
      expect(errors.first).to include("count > 2")
    end

    it "passes when count < N" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count < 5"],
      )
      instances = [item_class.new(1), item_class.new(2)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "fails when count < N is not satisfied" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count < 2"],
      )
      instances = [item_class.new(1), item_class.new(2), item_class.new(3)]
      errors = described_class.evaluate(collection, instances)
      expect(errors.length).to eq(1)
      expect(errors.first).to include("count < 2")
    end

    it "raises Unsupported condition for count != N (! is not in count operator charset)" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["count != 3"],
      )
      errors = described_class.evaluate(collection, [item_class.new(1)])
      expect(errors.length).to eq(1)
      expect(errors.first).to include("Unsupported condition")
    end
  end

  describe "block comparison operators" do
    let(:item_class) { Struct.new(:value) }

    it "supports > strict greater-than" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.value > 5 }"],
      )
      passing = [item_class.new(10), item_class.new(6)]
      expect(described_class.evaluate(collection, passing)).to eq([])

      failing = [item_class.new(5), item_class.new(10)]
      expect(described_class.evaluate(collection, failing).length).to eq(1)
    end

    it "supports < strict less-than" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.value < 100 }"],
      )
      passing = [item_class.new(1), item_class.new(99)]
      expect(described_class.evaluate(collection, passing)).to eq([])

      failing = [item_class.new(100), item_class.new(99)]
      expect(described_class.evaluate(collection, failing).length).to eq(1)
    end

    it "supports <= less-than-or-equal" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.value <= 10 }"],
      )
      passing = [item_class.new(10), item_class.new(5)]
      expect(described_class.evaluate(collection, passing)).to eq([])
    end

    it "supports != not-equal" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.value != 0 }"],
      )
      passing = [item_class.new(1), item_class.new(2)]
      expect(described_class.evaluate(collection, passing)).to eq([])

      failing = [item_class.new(0), item_class.new(2)]
      expect(described_class.evaluate(collection, failing).length).to eq(1)
    end
  end

  describe "literal types" do
    let(:item_class) { Struct.new(:score, :label, :active, :parent) }

    it "parses float literals" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.score >= 1.5 }"],
      )
      instances = [item_class.new(2.0), item_class.new(1.5)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "parses single-quoted string literals" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.label == 'ready' }"],
      )
      instances = [item_class.new(nil, "ready"), item_class.new(nil, "ready")]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "parses true literal" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.active == true }"],
      )
      instances = [item_class.new(nil, nil, true), item_class.new(nil, nil, true)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "parses false literal" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.active == false }"],
      )
      instances = [item_class.new(nil, nil, false)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "parses nil literal" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.parent == nil }"],
      )
      instances = [item_class.new(nil, nil, nil, nil)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "parses null as an alias for nil" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.parent == null }"],
      )
      instances = [item_class.new(nil, nil, nil, nil)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "parses negative integer literals" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.score > -1 }"],
      )
      instances = [item_class.new(0)]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end
  end

  describe "nested attribute paths" do
    let(:inner) { Struct.new(:name) }
    let(:middle) { Struct.new(:inner) }
    let(:outer) { Struct.new(:middle) }
    let(:item_class) { Struct.new(:outer) }

    it "walks i.outer.middle.inner.name" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ['all? { |i| i.outer.middle.inner.name == "leaf" }'],
      )
      instances = [
        item_class.new(outer.new(middle.new(inner.new("leaf")))),
      ]
      expect(described_class.evaluate(collection, instances)).to eq([])
    end

    it "fails when a nested value does not match" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ['all? { |i| i.outer.middle.inner.name == "leaf" }'],
      )
      instances = [
        item_class.new(outer.new(middle.new(inner.new("other")))),
      ]
      expect(described_class.evaluate(collection, instances).length).to eq(1)
    end
  end

  describe "error paths" do
    let(:item_class) { Struct.new(:value) }

    it "raises Unsupported predicate when the operator is missing" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ['all? { |i| i.value "missing-op" }'],
      )
      errors = described_class.evaluate(collection, [item_class.new(1)])
      expect(errors.length).to eq(1)
      expect(errors.first).to include("Unsupported predicate")
    end

    it "raises Unsupported literal for bareword tokens" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.value == bareword }"],
      )
      errors = described_class.evaluate(collection, [item_class.new(1)])
      expect(errors.length).to eq(1)
      expect(errors.first).to include("Unsupported literal")
    end

    it "raises when the block var is not i" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |x| x.value > 5 }"],
      )
      errors = described_class.evaluate(collection, [item_class.new(10)])
      expect(errors.length).to eq(1)
      expect(errors.first).to include("must reference i")
    end

    # Object.new specifically: the type guard has to run before the
    # validations call, so the argument must not respond to `validations`.
    it "returns no errors for an argument that is not a Collection" do
      expect(described_class.evaluate(Object.new, [])).to eq([])
    end

    it "rescues NoMethodError on undefined instance attributes" do
      collection = Lutaml::Lml::Collection.new(
        name: "test",
        validations: ["all? { |i| i.missing_attribute == 1 }"],
      )
      errors = described_class.evaluate(collection, [item_class.new(1)])
      expect(errors.length).to eq(1)
      expect(errors.first).to include("failed for at least one instance")
    end
  end
end
