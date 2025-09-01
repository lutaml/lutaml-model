require "spec_helper"

class TestModel < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :name, :string
end

class Container < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :my_ref, { ref: ["TestModel", :id] }
  attribute :multiple_refs, { ref: ["TestModel", :id] }, collection: true
end

RSpec.describe Lutaml::Model::Type::Reference do
  let(:target_object) { TestModel.new(id: "test-123", name: "Test Object") }
  
  before do
    # Register the target object in the store
    Lutaml::Model::Store.instance.register(target_object)
  end
  
  after do
    # Clean up the store after each test
    Lutaml::Model::Store.instance.clear
  end

  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with string value" do
      let(:value) { "test-123" }

      it "returns the value as-is (no auto-casting without metadata)" do
        is_expected.to eq("test-123")
      end
    end

    context "with Reference instance" do
      let(:reference) { described_class.new("TestModel", :id, "test-123") }
      let(:value) { reference }

      it { is_expected.to eq(reference) }
    end
  end

  describe ".cast_with_metadata" do
    subject(:cast_with_metadata) { described_class.cast_with_metadata(value, "TestModel", :id) }

    context "with string value" do
      let(:value) { "test-123" }

      it "creates a Reference instance with the correct metadata" do
        expect(cast_with_metadata).to be_a(described_class)
        expect(cast_with_metadata.model_class).to eq("TestModel")
        expect(cast_with_metadata.key_attribute).to eq(:id)
        expect(cast_with_metadata.key).to eq("test-123")
      end

      it "resolves the target object" do
        expect(cast_with_metadata.value).to eq(target_object)
      end
    end

    context "with nil value" do
      let(:value) { nil }

      it "creates a Reference instance with nil key" do
        expect(cast_with_metadata).to be_a(described_class)
        expect(cast_with_metadata.key).to be_nil
        expect(cast_with_metadata.value).to be_nil
      end
    end

    context "with Reference instance" do
      let(:existing_reference) { described_class.new("TestModel", :id, "test-123") }
      let(:value) { existing_reference }

      it "returns the existing reference unchanged" do
        expect(cast_with_metadata).to eq(existing_reference)
      end
    end

    context "with integer value" do
      let(:value) { 123 }

      it "converts to string and creates Reference" do
        expect(cast_with_metadata).to be_a(described_class)
        expect(cast_with_metadata.key).to eq(123)
      end
    end
  end

  describe "#initialize" do
    subject(:reference) { described_class.new("TestModel", :id, "test-123") }

    it "sets the model class" do
      expect(reference.model_class).to eq("TestModel")
    end

    it "sets the key attribute" do
      expect(reference.key_attribute).to eq(:id)
    end

    it "sets the key" do
      expect(reference.key).to eq("test-123")
    end

    it "resolves the value automatically" do
      expect(reference.value).to eq(target_object)
    end
  end

  describe "#with_key" do
    let(:reference) { described_class.new("TestModel", :id, "old-key") }
    subject(:new_reference) { reference.with_key("new-key") }

    it "creates a new reference with the new key" do
      expect(new_reference).to be_a(described_class)
      expect(new_reference.key).to eq("new-key")
      expect(new_reference.model_class).to eq("TestModel")
      expect(new_reference.key_attribute).to eq(:id)
    end

    it "does not modify the original reference" do
      new_reference
      expect(reference.key).to eq("old-key")
    end
  end

  describe "#resolve" do
    let(:reference) { described_class.new("TestModel", :id, "test-123") }

    context "when target object exists in store" do
      it "returns the resolved object" do
        expect(reference.resolve).to eq(target_object)
      end
    end

    context "when target object does not exist in store" do
      let(:reference) { described_class.new("TestModel", :id, "non-existent") }

      it "returns nil" do
        expect(reference.resolve).to be_nil
      end
    end
  end

  describe "#resolved?" do
    context "when reference resolves to an object" do
      let(:reference) { described_class.new("TestModel", :id, "test-123") }

      it "returns true" do
        expect(reference.resolved?).to be true
      end
    end

    context "when reference does not resolve" do
      let(:reference) { described_class.new("TestModel", :id, "non-existent") }

      it "returns false" do
        expect(reference.resolved?).to be false
      end
    end
  end

  describe ".serialize" do
    context "with Reference instance" do
      let(:reference) { described_class.new("TestModel", :id, "test-123") }
      subject(:serialized) { described_class.serialize(reference) }

      it "returns the key" do
        expect(serialized).to eq("test-123")
      end
    end

    context "with string value" do
      let(:value) { "direct-string" }
      subject(:serialized) { described_class.serialize(value) }

      it "returns the string" do
        expect(serialized).to eq("direct-string")
      end
    end

    context "with array of References" do
      let(:ref1) { described_class.new("TestModel", :id, "key1") }
      let(:ref2) { described_class.new("TestModel", :id, "key2") }
      let(:value) { [ref1, ref2] }
      subject(:serialized) { described_class.serialize(value) }

      it "returns string representation of array (default behavior)" do
        expect(serialized).to include("key1")
        expect(serialized).to include("key2")
      end
    end

    context "with nil value" do
      let(:value) { nil }
      subject(:serialized) { described_class.serialize(value) }

      it "returns empty string" do
        expect(serialized).to eq("")
      end
    end
  end

  describe "integration with models" do
    let(:container) { Container.new(id: "container-1") }

    context "single reference assignment" do
      it "auto-casts string to Reference instance" do
        container.my_ref = "test-123"
        
        expect(container.my_ref).to be_a(described_class)
        expect(container.my_ref.key).to eq("test-123")
        expect(container.my_ref.resolve).to eq(target_object)
      end
    end

    context "collection of references" do
      let(:target_object2) { TestModel.new(id: "test-456", name: "Test Object 2") }
      
      before do
        Lutaml::Model::Store.instance.register(target_object2)
      end

      it "auto-casts array of strings to Reference instances" do
        container.multiple_refs = ["test-123", "test-456"]
        
        expect(container.multiple_refs).to all(be_a(described_class))
        expect(container.multiple_refs.map(&:key)).to eq(["test-123", "test-456"])
        expect(container.multiple_refs.map(&:resolve)).to eq([target_object, target_object2])
      end
    end

    context "serialization round-trip" do
      it "maintains reference integrity through YAML serialization" do
        container.my_ref = "test-123"
        
        # Serialize to YAML
        yaml_data = container.to_yaml
        expect(yaml_data).to include("my_ref: test-123")
        
        # Deserialize from YAML
        loaded_container = Container.from_yaml(yaml_data)
        expect(loaded_container.my_ref).to be_a(described_class)
        expect(loaded_container.my_ref.key).to eq("test-123")
        expect(loaded_container.my_ref.resolve).to eq(target_object)
      end
    end
  end

  describe "error handling" do
    context "with invalid reference specification in attribute definition" do
      it "raises ArgumentError for non-array ref spec" do
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :invalid_ref, { ref: "InvalidSpec" }
          end
        end.to raise_error(ArgumentError, "ref: syntax requires an array [model_class, key_attribute]")
      end

      it "raises ArgumentError for array with wrong length" do
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :invalid_ref, { ref: ["OnlyOneElement"] }
          end
        end.to raise_error(ArgumentError, "ref: syntax requires an array [model_class, key_attribute]")
      end

      it "raises ArgumentError for array with too many elements" do
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :invalid_ref, { ref: ["Model", :attr, :extra] }
          end
        end.to raise_error(ArgumentError, "ref: syntax requires an array [model_class, key_attribute]")
      end
    end
  end
end
