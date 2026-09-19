# frozen_string_literal: true

require "spec_helper"

# lutaml-model#17 (order-insensitive equality) and #18 (structured
# diff), on top of the existing eql?/diff_with_score machinery.
RSpec.describe "Comparison family" do
  let(:phone_a) { Phone.new(kind: "home", number: "555-0100") }
  let(:phone_b) { Phone.new(kind: "work", number: "555-0177") }

  before do
    stub_const("Phone", Class.new(Lutaml::Model::Serializable) do
      attribute :kind, :string
      attribute :number, :string
    end)
    stub_const("Person", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
      attribute :phones, Phone, collection: true
    end)
  end

  describe "#same_as? (#17)" do
    it "treats reordered collections as equal" do
      a = Person.new(phones: [phone_a, phone_b])
      b = Person.new(phones: [phone_b, phone_a])
      expect(a == b).to be(false)
      expect(a.same_as?(b)).to be(true)
    end

    it "detects genuinely different collections regardless of order" do
      a = Person.new(phones: [phone_a, phone_b])
      b = Person.new(phones: [phone_a, Phone.new(kind: "fax", number: "9")])
      expect(a.same_as?(b)).to be(false)
    end

    it "respects strict mode" do
      a = Person.new(phones: [phone_a, phone_b])
      b = Person.new(phones: [phone_b, phone_a])
      expect(a.same_as?(b, ignore_element_order: false)).to be(false)
    end

    it "compares nested models recursively order-insensitively" do
      box1 = Class.new(Lutaml::Model::Serializable) do
        attribute :people, Person, collection: true
      end
      p1 = Person.new(name: "Ada", phones: [phone_a, phone_b])
      p2 = Person.new(name: "Ada", phones: [phone_b, phone_a])
      expect(box1.new(people: [p1]).same_as?(box1.new(people: [p2]))).to be(true)
    end
  end

  describe "#diff (#18)" do
    it "returns one entry per differing path" do
      a = Person.new(name: "Ada", age: 36, phones: [phone_a])
      b = Person.new(name: "Ada", age: 37, phones: [phone_b])
      entries = a.diff(b)

      paths = entries.map(&:path)
      expect(paths).to contain_exactly("age", "phones[0].kind", "phones[0].number")
    end

    it "reports length differences at the collection level" do
      a = Person.new(phones: [phone_a])
      b = Person.new(phones: [phone_a, phone_b])
      entries = a.diff(b)

      expect(entries.size).to eq(1)
      expect(entries.first.path).to eq("phones[1]")
      expect(entries.first.right).to eq(phone_b)
    end

    it "diffs equal objects to nothing" do
      a = Person.new(name: "Ada", age: 36, phones: [phone_a])
      expect(a.diff(a.dup)).to be_empty
    end
  end

  describe ".diff_with_score (#18, pre-existing)" do
    it "is reachable from model classes" do
      a = Person.new(age: 36)
      b = Person.new(age: 37)
      score, tree = Person.diff_with_score(a, b)
      expect(score).to be_a(Float)
      expect(tree).to include("age")
    end
  end
end
