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

  let(:required_test_record_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string, required: true
      attribute :age, :integer
    end
  end

  let(:test_record_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :age, :integer
      attribute :image, :string
      restrict :image, collection: 1..., pattern: /.*\.\w+$/
    end
  end

  before do
    stub_const("TestRecord", test_record_class)
    stub_const("RequiredTestRecord", required_test_record_class)
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
      "type must be set for an attribute",
    )
  end

  it "raises an error if required attributes are missing" do
    record = RequiredTestRecord.new
    expect do
      record.validate!
    end.to raise_error(Lutaml::Model::ValidationError,
                       "Missing required attribute: name")
  end

  it "does not raise an error when all required attributes are present" do
    record = RequiredTestRecord.new(name: "John", age: 30)
    expect { record.validate! }.not_to raise_error
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
            .with("Attribute name `#{method}` conflicts with a built-in method", anything)
        end

        it "logs a warning with the exact line of offense when method is `#{method}`" do
          # Capture the arguments passed to Logger.warn
          warn_args = nil
          allow(Lutaml::Model::Logger).to receive(:warn) do |message, location|
            warn_args = [message, location]
          end

          # Get the line number where the attribute is defined
          test_line = nil
          Class.new(Lutaml::Model::Serializable) do
            test_line = __LINE__ + 1 # Next line will be the attribute definition
            attribute method, :string
          end

          # Verify the warning was called with correct message
          expect(warn_args[0]).to eq("Attribute name `#{method}` conflicts with a built-in method")

          # Verify the caller location points to the exact line where attribute was defined
          expect(warn_args[1]).to be_a(Thread::Backtrace::Location)
          expect(warn_args[1].lineno).to eq(test_line)
          expect(warn_args[1].path).to include("attribute_spec.rb")
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

    context "when multiple attributes with conflicting names are defined" do
      before do
        allow(Lutaml::Model::Logger).to receive(:warn)
      end

      it "logs warnings with correct line numbers for each attribute" do
        # Capture all warning calls
        warning_calls = []
        allow(Lutaml::Model::Logger).to receive(:warn) do |message, location|
          warning_calls << [message, location]
        end

        # Define a class with multiple conflicting attributes
        hash_line = nil
        method_line = nil
        Class.new(Lutaml::Model::Serializable) do
          hash_line = __LINE__ + 1
          attribute :hash, :string
          method_line = __LINE__ + 1
          attribute :method, :string
        end

        # Verify both warnings were logged
        expect(warning_calls.length).to eq(2)

        # Check first warning (:hash)
        expect(warning_calls[0][0]).to eq("Attribute name `hash` conflicts with a built-in method")
        expect(warning_calls[0][1].lineno).to eq(hash_line)
        expect(warning_calls[0][1].path).to include("attribute_spec.rb")

        # Check second warning (:method)
        expect(warning_calls[1][0]).to eq("Attribute name `method` conflicts with a built-in method")
        expect(warning_calls[1][1].lineno).to eq(method_line)
        expect(warning_calls[1][1].path).to include("attribute_spec.rb")
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
      end.to raise_error(Lutaml::Model::InvalidAttributeOptionsError,
                         "Invalid options given for `name` [:foo]")
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

    context "when type is set and method_name is set" do
      let(:attribute) do
        described_class.new("name", :string, method_name: :tmp)
      end

      it "returns true" do
        expect(attribute.derived?).to be(true)
      end
    end

    context "when type is nil and method_name is set" do
      it "raises an error" do
        expect do
          described_class.new("name", nil, method_name: :tmp)
        end.to raise_error(ArgumentError, "type must be set for an attribute")
      end
    end
  end

  describe "#default via DefaultValueResolver" do
    let(:register) { Lutaml::Model::Config.default_register }

    def create_resolver(attribute)
      Lutaml::Model::Services::DefaultValueResolver.new(attribute, register, nil)
    end

    context "when default is not set" do
      let(:attribute) { described_class.new("name", :string) }

      it "returns uninitialized" do
        expect(create_resolver(attribute).default).to be(Lutaml::Model::UninitializedClass.instance)
      end
    end

    context "when default is set as a proc" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: -> { "John" })
        expect(create_resolver(attribute).default).to eq("John")
      end

      it "returns the value casted to correct type" do
        file = Pathname.new("avatar.png")
        attribute = described_class.new("image", :string, default: -> { file })

        expect(create_resolver(attribute).default).to eq("avatar.png")
      end
    end

    context "when default is set as value" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: "John Doe")
        expect(create_resolver(attribute).default).to eq("John Doe")
      end

      it "returns the value casted to correct type" do
        attribute = described_class.new("age", :integer, default: "24")
        expect(create_resolver(attribute).default).to eq(24)
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
