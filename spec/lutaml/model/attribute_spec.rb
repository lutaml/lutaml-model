require "spec_helper"
require_relative "../../../lib/lutaml/model"
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
    # Test that all names are allowed (no errors raised)
    # Only specific names trigger warnings
    before do
      allow(Lutaml::Model::Logger).to receive(:warn)
    end

    # Names that should NOT trigger warnings
    # These are common Ruby methods that work fine when overridden
    (Lutaml::Model::Serializable.instance_methods - described_class.warn_on_override_names).each do |method|
      it "does not warn when attribute name is `#{method}`" do
        Class.new(Lutaml::Model::Serializable) do
          attribute method, :string
        end

        expect(Lutaml::Model::Logger).not_to have_received(:warn)
      end
    end

    # Names that SHOULD trigger warnings
    # These are methods where accidental override is likely to cause issues
    described_class.warn_on_override_names.each do |method|
      next unless Lutaml::Model::Serializable.method_defined?(method)

      it "logs a warning when attribute name is `#{method}`" do
        Class.new(Lutaml::Model::Serializable) do
          attribute method, :string
        end

        expect(Lutaml::Model::Logger)
          .to have_received(:warn)
          .with(a_string_including("Attribute `#{method}` overrides a method"), anything)
      end

      it "logs a warning with the exact line of offense when attribute name is `#{method}`" do
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
        expect(warn_args[0]).to include("Attribute `#{method}` overrides a method")

        # Verify the caller location points to the exact line where attribute was defined
        expect(warn_args[1]).to be_a(Thread::Backtrace::Location)
        expect(warn_args[1].lineno).to eq(test_line)
        expect(warn_args[1].path).to include("attribute_spec.rb")
      end
    end

    context "when attribute name conflicts with a non-Serializable method" do
      it "does not warn for `display` (Kernel method)" do
        Class.new(Lutaml::Model::Serializable) do
          attribute :display, :string
        end

        expect(Lutaml::Model::Logger).not_to have_received(:warn)
      end

      it "does not warn for `validate` (designed to be overridden)" do
        Class.new(Lutaml::Model::Serializable) do
          attribute :validate, :string
        end

        expect(Lutaml::Model::Logger).not_to have_received(:warn)
      end
    end

    context "when multiple attributes with conflicting names are defined" do
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
        expect(warning_calls[0][0]).to include("Attribute `hash` overrides a method")
        expect(warning_calls[0][1].lineno).to eq(hash_line)
        expect(warning_calls[0][1].path).to include("attribute_spec.rb")

        # Check second warning (:method)
        expect(warning_calls[1][0]).to include("Attribute `method` overrides a method")
        expect(warning_calls[1][1].lineno).to eq(method_line)
        expect(warning_calls[1][1].path).to include("attribute_spec.rb")
      end
    end

    context "when attribute name does not conflict with any method" do
      it "does not log any warning" do
        Class.new(Lutaml::Model::Serializable) do
          attribute :my_custom_attribute, :string
        end

        expect(Lutaml::Model::Logger).not_to have_received(:warn)
      end
    end
  end

  describe "#validate_options!" do
    let(:validate_options) { name_attr.method(:validate_options!) }

    Lutaml::Model::Attribute::ALLOWED_OPTIONS.each do |option|
      it "return true if option is `#{option}`" do
        if option == :xsd_type
          expect do
            result = validate_options.call({ option => "value" })
            expect(result).to be(true)
          end.to output.to_stderr
        else
          expect(validate_options.call({ option => "value" })).to be(true)
        end
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

  describe "#default" do
    let(:register) { Lutaml::Model::Config.default_register }
    let(:instance) { nil }

    context "when default is not set" do
      let(:attribute) { described_class.new("name", :string) }

      it "returns uninitialized" do
        expect(attribute.default(register, instance)).to be(Lutaml::Model::UninitializedClass.instance)
      end
    end

    context "when default is set as a proc" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: -> { "John" })
        expect(attribute.default(register, instance)).to eq("John")
      end

      it "returns the value casted to correct type" do
        file = Pathname.new("avatar.png")
        attribute = described_class.new("image", :string, default: -> { file })

        expect(attribute.default(register, instance)).to eq("avatar.png")
      end
    end

    context "when default is set as value" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: "John Doe")
        expect(attribute.default(register, instance)).to eq("John Doe")
      end

      it "returns the value casted to correct type" do
        attribute = described_class.new("age", :integer, default: "24")
        expect(attribute.default(register, instance)).to eq(24)
      end

      it "casts a String default to Integer for :integer attribute" do
        attribute = described_class.new("count", :integer, default: "42")
        expect(attribute.default(register, instance)).to eq(42)
      end
    end

    context "with instance context" do
      # Exercise instance_exec: the proc reads `name` from the instance,
      # which is only resolvable when the proc is executed in the
      # instance's context (`instance_object.instance_exec(&proc)`).
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :greeting, :string, default: -> { "Hello, #{name}" }
        end
      end

      it "executes and casts the proc in instance context" do
        instance = model_class.new(name: "Alice")
        attribute = model_class.attributes[:greeting]
        expect(attribute.default(register, instance)).to eq("Hello, Alice")
      end

      it "bypasses the default cache when instance_object is given" do
        attribute = model_class.attributes[:greeting]
        first  = attribute.default(register, model_class.new(name: "Alice"))
        second = attribute.default(register, model_class.new(name: "Bob"))
        expect(first).to eq("Hello, Alice")
        expect(second).to eq("Hello, Bob")
      end
    end
  end

  describe "#default_value" do
    let(:register) { Lutaml::Model::Config.default_register }
    let(:instance) { nil }

    context "when default is a static value" do
      it "returns the static value uncast" do
        attribute = described_class.new("name", :string, default: "John")
        expect(attribute.default_value(register, instance)).to eq("John")
      end
    end

    context "when default is a proc without instance context" do
      it "executes the proc" do
        attribute = described_class.new("count", :integer, default: -> { 42 })
        expect(attribute.default_value(register, instance)).to eq(42)
      end
    end

    context "when default is a proc with instance context" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :greeting, :string, default: -> { "Hello, #{name}" }
        end
      end

      it "executes the proc in the instance context (reads instance attribute)" do
        instance = model_class.new(name: "Alice")
        attribute = model_class.attributes[:greeting]
        expect(attribute.default_value(register, instance)).to eq("Hello, Alice")
      end
    end
  end

  describe "#default_set?" do
    let(:register) { Lutaml::Model::Config.default_register }
    let(:instance) { nil }

    it "returns false when default is not set" do
      attribute = described_class.new("name", :string)
      expect(attribute.default_set?(register, instance)).to be(false)
    end

    it "returns true when default is a static value" do
      attribute = described_class.new("name", :string, default: "John")
      expect(attribute.default_set?(register, instance)).to be(true)
    end

    it "returns true when default is a proc" do
      attribute = described_class.new("name", :string, default: -> { "John" })
      expect(attribute.default_set?(register, instance)).to be(true)
    end
  end

  describe "#validate_value!" do
    let(:register) { Lutaml::Model::Config.default_register }
    let(:model) { Class.new(Lutaml::Model::Serializable).new }

    context "when value is nil and the attribute has no default" do
      it "treats nil-no-default as a permissible non-required value" do
        attr = described_class.new("name", :string)
        expect { attr.validate_value!(nil, register, instance_object: model) }
          .not_to raise_error
      end
    end

    context "when value is nil and the attribute has a default" do
      it "uses the default value for validation" do
        attr = described_class.new("name", :string, default: "John")
        expect { attr.validate_value!(nil, register, instance_object: model) }
          .not_to raise_error
      end

      it "executes a proc default in the instance context (instance_exec preserved)" do
        # Regression: validate_value! must thread instance_object through
        # default(register, instance_object) which calls instance_exec on
        # the Proc. Verify by having the Proc read an instance attribute.
        model_class = Class.new(Lutaml::Model::Serializable) do
          attribute :prefix, :string, values: %w[Mr Ms Dr]
          attribute :name, :string, values: %w[Alice Bob],
                                    default: -> { "#{prefix}_default" }
        end
        instance = model_class.new(prefix: "Dr")
        attr = model_class.attributes[:name]
        expect { attr.validate_value!(nil, register, instance_object: instance) }
          .to raise_error(Lutaml::Model::InvalidValueError) do |error|
            # The error carries the value that was used for validation.
            # If instance_exec ran, value is "Dr_default"; if not, error
            # would never fire (proc would crash before reaching validation).
            expect(error.message).to include("Dr_default")
          end
      end
    end

    context "when value is uninitialized" do
      it "short-circuits without raising" do
        uninit = Lutaml::Model::UninitializedClass.instance
        attr = described_class.new("name", :string)
        expect { attr.validate_value!(uninit, register, instance_object: model) }
          .not_to raise_error
      end
    end
  end

  describe "Model initialization with proc defaults" do
    # Regression: Serialize#determine_value previously called default_set?
    # + default separately, executing the Proc twice for each omitted
    # attribute. Verify single-execution by counting side effects.
    it "executes a proc default exactly once when the attribute is omitted" do
      counter = 0
      model_class = Class.new(Lutaml::Model::Serializable) do
        attribute :count, :integer, default: -> { counter += 1 }
      end

      instance = model_class.new
      expect(instance.count).to eq(1)
      expect(counter).to eq(1)
    end
  end

  describe "#deep_dup" do
    let(:duplicate_attribute) { Lutaml::Model::Utils.deep_dup(attribute) }

    context "when object does not include DeepDupable" do
      it "falls back to dup for plain objects" do
        plain = Struct.new(:value).new("hello")
        result = Lutaml::Model::Utils.deep_dup(plain)
        expect(result.value).to eq("hello")
        expect(result).not_to equal(plain)
      end
    end

    context "when Attribute is deep_duplicated" do
      let(:attribute) { described_class.new("name", :string) }

      it "creates independent copies of options" do
        duplicate_attribute
        attribute.options[:foo] = "bar"
        expect(duplicate_attribute.options).not_to include(:foo)
      end
    end
  end

  describe "#type caching" do
    let(:attr) { described_class.new("name", :string) }

    it "returns same object on repeated calls with nil register" do
      result1 = attr.type
      result2 = attr.type
      expect(result1).to equal(result2)
    end

    it "returns same object on repeated calls with :default" do
      result1 = attr.type(:default)
      result2 = attr.type(:default)
      expect(result1).to equal(result2)
    end

    it "caches non-default register path by context identity" do
      ctx = Lutaml::Model::GlobalContext.default_context
      result1 = attr.type(ctx)
      result2 = attr.type(ctx)
      expect(result1).to equal(result2)
    end
  end

  describe "#cast_element" do
    let(:register) { Lutaml::Model::Config.default_register }

    context "when type validation is enabled" do
      # Create a dummy invalid type class
      let(:invalid_type_class) do
        Class.new do
          def self.cast(value)
            value
          end

          def self.name
            "InvalidTypeClass"
          end
        end
      end

      # Create a valid Type::Value subclass
      let(:valid_value_type_class) do
        Class.new(Lutaml::Model::Type::Value) do
          def self.cast(value, _options = {})
            value&.to_s
          end

          def self.name
            "ValidValueType"
          end
        end
      end

      # Create a valid Serializable subclass
      let(:valid_serializable_class) do
        Class.new(Lutaml::Model::Serializable) do
          def self.name
            "ValidSerializableType"
          end
        end
      end

      context "with invalid type that doesn't inherit from Serializable or Type::Value" do
        it "raises InvalidAttributeTypeError" do
          attribute = described_class.new("test_attr", invalid_type_class)

          expect { attribute.cast_element("test_value", register) }
            .to raise_error(
              Lutaml::Model::InvalidAttributeTypeError,
              /Invalid type .*InvalidTypeClass.* for attribute `test_attr`/,
            )
        end
      end

      context "with valid Type::Value subclass" do
        it "successfully casts the value" do
          attribute = described_class.new("test_attr", valid_value_type_class)
          result = attribute.cast_element("test_value", register)

          expect(result).to eq("test_value")
        end
      end

      context "with valid Serializable subclass" do
        it "successfully casts the value" do
          attribute = described_class.new("test_attr", valid_serializable_class)

          expect { attribute.cast_element({}, register) }.not_to raise_error
        end
      end

      context "with class that includes Serialize module" do
        let(:serialize_including_class) do
          Class.new do
            include Lutaml::Model::Serialize

            attribute :name, :string

            def self.name
              "SerializeIncludingClass"
            end
          end
        end

        it "successfully casts the value" do
          attribute = described_class.new("test_attr",
                                          serialize_including_class)

          expect { attribute.cast_element({}, register) }.not_to raise_error
        end
      end

      context "with built-in types" do
        it "works with string type" do
          attribute = described_class.new("test_attr", :string)
          result = attribute.cast_element("test_value", register)

          expect(result).to eq("test_value")
        end

        it "works with integer type" do
          attribute = described_class.new("test_attr", :integer)
          result = attribute.cast_element("42", register)

          expect(result).to eq(42)
        end

        it "works with boolean type" do
          attribute = described_class.new("test_attr", :boolean)
          result = attribute.cast_element("true", register)

          expect(result).to be(true)
        end
      end

      context "with Reference type" do
        it "handles Reference type specially without validation" do
          attribute = described_class.new(
            "test_attr",
            Lutaml::Model::Type::Reference,
            ref_model_class: "TestModel",
            ref_key_attribute: :id,
          )

          # Reference type should bypass the validation check
          expect do
            attribute.cast_element("test_key", register)
          end.not_to raise_error
        end
      end

      context "with Hash type and hash value" do
        it "creates new instance without validation when value is a Hash and type is not hash_type" do
          attribute = described_class.new("test_attr", valid_serializable_class)
          hash_value = { "key" => "value" }

          result = attribute.cast_element(hash_value, register)
          expect(result).to be_a(valid_serializable_class)
        end

        it "validates when value is not a Hash" do
          attribute = described_class.new("test_attr", invalid_type_class)

          expect { attribute.cast_element("not_a_hash", register) }
            .to raise_error(Lutaml::Model::InvalidAttributeTypeError)
        end
      end
    end
  end
end
