require "spec_helper"

class TestSerializable < Lutaml::Model::Serializable
  attribute :name, :string, values: ["Alice", "Bob", "Charlie"]
  attribute :email, :string, pattern: /.*?\S+@.+\.\S+/
  attribute :age, :integer, collection: 1..3

  xml do
    element "test"
    map_element "name", to: :name
    map_element "age", to: :age
  end

  json do
    map "name", to: :name
    map "age", to: :age
  end

  yaml do
    map "name", to: :name
    map "age", to: :age
  end

  toml do
    map "name", to: :name
    map "age", to: :age
  end
end

RSpec.describe Lutaml::Model::Serializable do
  let(:valid_instance) do
    TestSerializable.new(name: "Alice", age: [30], email: "alice@gmail.com")
  end

  let(:invalid_instance) do
    TestSerializable.new(name: "David", age: [25, 30, 35, 40],
                         email: "david@gmail")
  end

  describe "serialization methods" do
    it "does not raise validation errors when calling to_xml" do
      expect { invalid_instance.to_xml }.not_to raise_error
    end

    it "does not raise validation errors when calling to_json" do
      expect { invalid_instance.to_json }.not_to raise_error
    end

    it "does not raise validation errors when calling to_yaml" do
      expect { invalid_instance.to_yaml }.not_to raise_error
    end

    it "does not raise validation errors when calling to_toml" do
      expect { invalid_instance.to_toml }.not_to raise_error
    end
  end

  describe "setting attributes" do
    it "does not raise validation errors when setting valid attributes" do
      expect { valid_instance.name = "Bob" }.not_to raise_error
      expect { valid_instance.age = [25, 30] }.not_to raise_error
    end

    it "does not raise validation errors when setting invalid attributes" do
      expect { invalid_instance.name = "David" }.not_to raise_error
      expect { invalid_instance.age = [25, 30, 35, 40] }.not_to raise_error
    end
  end

  describe "validate method" do
    it "returns errors for invalid attributes" do
      errors = invalid_instance.validate
      expect(errors).not_to be_empty
      expect(errors[0]).to be_a(Lutaml::Model::InvalidValueError)
      expect(errors[1]).to be_a(Lutaml::Model::PatternNotMatchedError)
      expect(errors[2]).to be_a(Lutaml::Model::CollectionCountOutOfRangeError)
    end
  end

  describe "validate! method" do
    it "raises ValidationError for invalid attributes" do
      expect do
        invalid_instance.validate!
      end.to raise_error(Lutaml::Model::ValidationError)
    end

    it "does not raise ValidationError for valid attributes" do
      expect { valid_instance.validate! }.not_to raise_error
    end
  end

  # Regression: valid_pattern! must short-circuit non-string values instead of
  # feeding nil / UninitializedClass to Regexp#match? (which raises TypeError).
  describe "pattern with absent or nil values" do
    it "does not raise when an optional patterned string is omitted" do
      instance = TestSerializable.new(name: "Alice", age: [30])

      errors = nil
      expect { errors = instance.validate }.not_to raise_error
      expect(errors).to be_none do |e|
        e.is_a?(Lutaml::Model::PatternNotMatchedError)
      end
    end

    it "skips nil elements in a patterned collection" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :codes, :string, collection: true, pattern: /\A[A-Z]+\z/
        key_value { map "codes", to: :codes }
      end

      expect(klass.new(codes: ["ABC", nil, "DEF"]).validate).to be_empty
      expect(klass.new(codes: ["ABC", "bad"]).validate).not_to be_empty
    end

    # valid_collection! must return truthy on success so validate_value!'s &&
    # chain still reaches pattern validation for a bounded-range collection.
    it "still runs pattern validation after a valid bounded-range collection" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :codes, :string, collection: 1..2, pattern: /\A[A-Z]+\z/
        key_value { map "codes", to: :codes }
      end

      expect(klass.new(codes: ["ABC"]).validate).to be_empty
      expect(klass.new(codes: ["bad"]).validate)
        .to include(an_instance_of(Lutaml::Model::PatternNotMatchedError))
    end
  end

  # Regression: enum (values:) on a collection must validate each element,
  # not compare the whole coerced collection against the allowed set.
  describe "enum on collection attributes" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :tags, :string, collection: true, values: %w[a b c]
        key_value { map "tags", to: :tags }
      end
    end

    it "accepts a single valid value coerced into the collection" do
      expect(klass.new(tags: ["a"]).validate).to be_empty
    end

    it "accepts multiple valid values" do
      expect(klass.new(tags: %w[a b]).validate).to be_empty
    end

    it "rejects a collection containing a disallowed element" do
      expect(klass.new(tags: %w[a z]).validate)
        .to include(an_instance_of(Lutaml::Model::InvalidValueError))
    end
  end

  # Regression: a collection of nested models must recurse into every element
  # so a grandchild's own validation errors surface on the parent.
  describe "nested model collection validation" do
    let(:child_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :status, :string, values: %w[ok fine]
        key_value { map "status", to: :status }
      end
    end

    let(:parent_class) do
      child = child_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :items, child, collection: true
        key_value { map "items", to: :items }
      end
    end

    it "surfaces an invalid grandchild in a model collection" do
      parent = parent_class.new(
        items: [child_class.new(status: "ok"), child_class.new(status: "BAD")],
      )

      expect(parent.validate)
        .to include(an_instance_of(Lutaml::Model::InvalidValueError))
    end

    it "returns no errors when every model element is valid" do
      parent = parent_class.new(
        items: [child_class.new(status: "ok"), child_class.new(status: "fine")],
      )

      expect(parent.validate).to be_empty
    end
  end
end
