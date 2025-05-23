require "spec_helper"
require "lutaml/model"
require "pathname"

RSpec.describe Lutaml::Model::Attribute do
  subject(:name_attr) do
    described_class.new("name", :string)
  end

  let(:method_attr) do
    described_class.new("name", nil, method_name: nil)
  end

  let(:test_record_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :age, :integer
      attribute :image, :string
    end
  end

  before do
    stub_const("TestRecord", test_record_class)
  end

  it "cast to integer when assigning age" do
    obj = TestRecord.new

    expect { obj.age = "20" }.to change { obj.age }.from(nil).to(20)
  end

  it "cast to string when assigning image file" do
    obj = TestRecord.new

    expect { obj.image = Pathname.new("avatar.png") }
      .to change { obj.image }
      .from(nil)
      .to("avatar.png")
  end

  it "raises error if both type and method_name are not given" do
    expect { method_attr }.to raise_error(
      ArgumentError,
      "method or type must be set for an attribute",
    )
  end

  describe "#validate_name!" do
    Lutaml::Model::Serializable.instance_methods.each do |method|
      if Lutaml::Model::Attribute::ALLOW_OVERRIDING.include?(method)
        before do
          allow(Lutaml::Model::Logger).to receive(:warn)
        end

        it "does not raise an error when method is `#{method}`" do
          expect do
            Class.new(Lutaml::Model::Serializable) do
              attribute method, :string
            end
          end.not_to raise_error
        end

        it "logs a warning, when method is `#{method}`" do
          Class.new(Lutaml::Model::Serializable) do
            attribute method, :string
          end

          expect(Lutaml::Model::Logger)
            .to have_received(:warn)
            .with("Attribute name `#{method}` conflicts with a built-in method")
        end
      else
        it "raise exception, when method is `#{method}`" do
          expect do
            Class.new(Lutaml::Model::Serializable) do
              attribute method, :string
            end
          end.to raise_error(
            Lutaml::Model::InvalidAttributeNameError,
            "Attribute name '#{method}' is not allowed",
          )
        end
      end
    end
  end

  describe "#validate_options!" do
    let(:validate_options) { name_attr.method(:validate_options!) }

    Lutaml::Model::Attribute::ALLOWED_OPTIONS.each do |option|
      it "return true if option is `#{option}`" do
        expect(validate_options.call({ option => "value" })).to be(true)
      end
    end

    it "raise exception if option is not allowed" do
      expect do
        validate_options.call({ foo: "bar" })
      end.to raise_error(StandardError, "Invalid options given for `name` [:foo]")
    end

    it "raise exception if pattern is given with non string type" do
      age_attr = described_class.new("age", :integer)

      expect do
        age_attr.send(:validate_options!, { pattern: /[A-Za-z ]/ })
      end.to raise_error(
        StandardError,
        "Invalid option `pattern` given for `age`, `pattern` is only allowed for :string type",
      )
    end
  end

  describe "#derived?" do
    context "when type is set" do
      let(:attribute) { described_class.new("name", :string) }

      it "returns false" do
        expect(attribute.derived?).to be(false)
      end
    end

    context "when type is nil and method_name is set" do
      let(:attribute) { described_class.new("name", nil, method_name: :tmp) }

      it "returns true" do
        expect(attribute.derived?).to be(true)
      end
    end
  end

  describe "#default" do
    context "when default is not set" do
      let(:attribute) { described_class.new("name", :string) }

      it "returns uninitialized" do
        expect(attribute.default).to be(Lutaml::Model::UninitializedClass.instance)
      end
    end

    context "when default is set as a proc" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: -> { "John" })
        expect(attribute.default).to eq("John")
      end

      it "returns the value casted to correct type" do
        file = Pathname.new("avatar.png")
        attribute = described_class.new("image", :string, default: -> { file })

        expect(attribute.default).to eq("avatar.png")
      end
    end

    context "when default is set as value" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: "John Doe")
        expect(attribute.default).to eq("John Doe")
      end

      it "returns the value casted to correct type" do
        attribute = described_class.new("age", :integer, default: "24")
        expect(attribute.default).to eq(24)
      end
    end
  end

  describe "#deep_dup" do
    let(:duplicate_attribute) { Lutaml::Model::Utils.deep_dup(attribute) }

    context "when deep_dup method is not defined and instance is deep_duplicated" do
      let(:attribute) { described_class.new("name", :string) }

      before do
        described_class.alias_method :orig_deep_dup, :deep_dup
        described_class.undef_method :deep_dup
      end

      after do
        described_class.alias_method :deep_dup, :orig_deep_dup
        attribute.options.delete(:foo)
      end

      it "confirms that options values are linked of original and duplicate instances" do
        duplicate_attribute
        attribute.options[:foo] = "bar"
        expect(duplicate_attribute.options).to include(:foo)
      end
    end

    context "when deep_dup method is defined and instance is deep_duplicated" do
      let(:attribute) { described_class.new("name", :string) }

      it "confirms that options values are not linked of original and duplicate instances" do
        duplicate_attribute
        attribute.options[:foo] = "bar"
        expect(duplicate_attribute.options).not_to include(:foo)
      end
    end
  end
end
