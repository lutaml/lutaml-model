# frozen_string_literal: true

class WithEnumValues < Lutaml::Model::Serializable
  attribute :first, Lutaml::Model::Type::String, values: ["one", "two", "three"]
end

RSpec.describe Lutaml::Model do
  it "has a version number" do
    expect(Lutaml::Model::VERSION).not_to be_nil
  end

  context "when value is not allowed" do
    it "raises error when assigning after creation" do
      object = WithEnumValues.new({ first: "one" })

      expect { object.first = "four" }
        .to raise_error(Lutaml::Model::InvalidValueError)
    end

    it "raises error when assigning when creation" do
      expect { WithEnumValues.new({ first: "five" }) }
        .to raise_error(Lutaml::Model::InvalidValueError)
    end
  end

  context "when value is allowed" do
    it "changes value when assigning after creation" do
      object = WithEnumValues.new({ first: "one" })

      expect { object.first = "two" }
        .to change { object.first }
        .from("one")
        .to("two")
    end

    it "assign value when creating" do
      object = WithEnumValues.new({ first: "three" })

      expect(object.first).to eq("three")
    end
  end
end
