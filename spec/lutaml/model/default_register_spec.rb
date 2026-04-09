# frozen_string_literal: true

# rubocop:disable all
# lutaml_default_register is not a predicate - it returns Symbol or nil (the register ID)

require "spec_helper"

RSpec.describe "lutaml_default_register" do
  describe "class method" do
    context "when not overridden" do
      let(:klass) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
        end
      end

      it "returns nil by default" do
        expect(klass.lutaml_default_register).to be_nil
      end
    end

    context "when overridden in subclass" do
      let(:base_klass) do
        Class.new(Lutaml::Model::Serializable) do
          # rubocop:disable Naming/PredicateName
          # Not a predicate - returns Symbol or nil, not boolean
          def self.lutaml_default_register
            :custom_register
          end
          # rubocop:enable Naming/PredicateName
        end
      end

      let(:child_klass) do
        Class.new(base_klass) do
          attribute :name, :string
        end
      end

      it "inherits the value from parent" do
        expect(child_klass.lutaml_default_register).to eq(:custom_register)
      end

      it "can be overridden in child" do
        child_with_override = Class.new(base_klass) do
          # rubocop:disable Naming/PredicateName
          def self.lutaml_default_register
            :another_register
          end
          # rubocop:enable Naming/PredicateName
        end
        expect(child_with_override.lutaml_default_register).to eq(:another_register)
      end
    end
  end

  describe "instance initialization" do
    let(:custom_register) do
      Lutaml::Model::Register.new(:custom_register)
    end

    before do
      Lutaml::Model::GlobalRegister.register(custom_register)
      Lutaml::Model::Config.default_register = :default
    end

    after do
      Lutaml::Model::GlobalRegister.remove(:custom_register)
      Lutaml::Model::GlobalRegister.remove(:versioned_register)
    end

    context "when class has lutaml_default_register set" do
      let(:versioned_register) do
        Lutaml::Model::Register.new(:versioned_register)
      end

      let(:versioned_klass) do
        Class.new(Lutaml::Model::Serializable) do
          # rubocop:disable Naming/PredicateName
          def self.lutaml_default_register
            :versioned_register
          end
          # rubocop:enable Naming/PredicateName

          attribute :value, :string

          xml do
            root "test"
            map_element "value", to: :value
          end
        end
      end

      before do
        Lutaml::Model::GlobalRegister.register(versioned_register)
      end

      it "uses lutaml_default_register when no explicit register provided" do
        instance = versioned_klass.new
        expect(instance.lutaml_register).to eq(:versioned_register)
      end

      it "uses Config.default_register when class does not define lutaml_default_register" do
        regular_klass = Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            root "regular"
          end
        end

        instance = regular_klass.new
        expect(instance.lutaml_register).to eq(:default)
      end

      it "explicit register option takes precedence over lutaml_default_register" do
        instance = versioned_klass.new({}, register: :custom_register)
        expect(instance.lutaml_register).to eq(:custom_register)
      end
    end

    context "precedence order" do
      let(:register_class_default) do
        Lutaml::Model::Register.new(:class_default)
      end

      let(:klass_with_default) do
        Class.new(Lutaml::Model::Serializable) do
          # rubocop:disable Naming/PredicateName
          def self.lutaml_default_register
            :class_default
          end
          # rubocop:enable Naming/PredicateName

          attribute :name, :string

          xml do
            root "test"
            map_element "name", to: :name
          end
        end
      end

      before do
        Lutaml::Model::GlobalRegister.register(register_class_default)
      end

      it "precedence: explicit register > lutaml_default_register > Config.default_register" do
        # Explicit register wins
        instance1 = klass_with_default.new({}, register: :custom_register)
        expect(instance1.lutaml_register).to eq(:custom_register)

        # lutaml_default_register is used when no explicit register
        instance2 = klass_with_default.new
        expect(instance2.lutaml_register).to eq(:class_default)
      end

      it "Config.default_register is used when neither explicit nor class default" do
        regular_klass = Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            root "regular"
          end
        end

        instance = regular_klass.new
        expect(instance.lutaml_register).to eq(:default)
      end
    end

    context "with nested attributes" do
      let(:parent_register) do
        Lutaml::Model::Register.new(:parent_register)
      end

      # rubocop:disable Metrics/MethodLength
      let!(:nested_test) do
        child_klass = Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            root "child"
            map_element "value", to: :value
          end
        end

        parent_klass = Class.new(Lutaml::Model::Serializable) do
          # rubocop:disable Naming/PredicateName
          def self.lutaml_default_register
            :parent_register
          end
          # rubocop:enable Naming/PredicateName

          attribute :child, child_klass

          xml do
            root "parent"
            map_element "child", to: :child
          end
        end

        Lutaml::Model::GlobalRegister.register(parent_register)

        { parent: parent_klass, child: child_klass, register: parent_register }
      end
      # rubocop:enable Metrics/MethodLength

      after do
        Lutaml::Model::GlobalRegister.remove(:parent_register)
      end

      it "parent instance uses parent_register" do
        instance = nested_test[:parent].new
        expect(instance.lutaml_register).to eq(:parent_register)
      end
    end
  end

  describe "with versioned schema use case (MML example)" do
    let(:v2_register) do
      Lutaml::Model::Register.new(:mml_v2)
    end

    let(:v3_register) do
      Lutaml::Model::Register.new(:mml_v3)
    end

    before do
      Lutaml::Model::GlobalRegister.register(v2_register)
      Lutaml::Model::GlobalRegister.register(v3_register)
      Lutaml::Model::Config.default_register = :default
    end

    after do
      Lutaml::Model::GlobalRegister.remove(:mml_v2)
      Lutaml::Model::GlobalRegister.remove(:mml_v3)
    end

    it "allows versioned base classes with different defaults" do
      v2_base = Class.new(Lutaml::Model::Serializable) do
        # rubocop:disable Naming/PredicateName
        def self.lutaml_default_register
          :mml_v2
        end
        # rubocop:enable Naming/PredicateName
      end

      v3_base = Class.new(Lutaml::Model::Serializable) do
        # rubocop:disable Naming/PredicateName
        def self.lutaml_default_register
          :mml_v3
        end
        # rubocop:enable Naming/PredicateName
      end

      v2_math = Class.new(v2_base) do
        attribute :value, :string

        xml do
          root "math"
          map_element "value", to: :value
        end
      end

      v3_math = Class.new(v3_base) do
        attribute :value, :string

        xml do
          root "math"
          map_element "value", to: :value
        end
      end

      # Without explicit register, uses version-specific default
      v2_instance = v2_math.new
      v3_instance = v3_math.new

      expect(v2_instance.lutaml_register).to eq(:mml_v2)
      expect(v3_instance.lutaml_register).to eq(:mml_v3)

      # Explicit register still works to override
      v2_with_v3 = v2_math.new({}, register: :mml_v3)
      expect(v2_with_v3.lutaml_register).to eq(:mml_v3)
    end
  end

  describe "extract_register_id resolution" do
    context "when called on class without lutaml_default_register" do
      let(:klass) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
        end
      end

      it "falls back to Config.default_register when no register passed" do
        result = klass.extract_register_id(nil)
        expect(result).to eq(:default)
      end

      it "returns explicit register when passed" do
        result = klass.extract_register_id(:custom)
        expect(result).to eq(:custom)
      end
    end

    context "when called on class with lutaml_default_register" do
      let(:my_register) do
        Lutaml::Model::Register.new(:my_default)
      end

      let(:klass) do
        Class.new(Lutaml::Model::Serializable) do
          # rubocop:disable Naming/PredicateName
          def self.lutaml_default_register
            :my_default
          end
          # rubocop:enable Naming/PredicateName

          attribute :name, :string
        end
      end

      before do
        Lutaml::Model::GlobalRegister.register(my_register)
      end

      after do
        Lutaml::Model::GlobalRegister.remove(:my_default)
      end

      it "uses lutaml_default_register when no register passed" do
        result = klass.extract_register_id(nil)
        expect(result).to eq(:my_default)
      end

      it "explicit register takes precedence" do
        result = klass.extract_register_id(:other_register)
        expect(result).to eq(:other_register)
      end
    end
  end

  describe "edge cases" do
    let(:test_register) do
      Lutaml::Model::Register.new(:test_register)
    end

    before do
      Lutaml::Model::GlobalRegister.register(test_register)
    end

    after do
      Lutaml::Model::GlobalRegister.remove(:test_register)
    end

    it "handles string register parameter correctly" do
      klass = Class.new(Lutaml::Model::Serializable) do
        # rubocop:disable Naming/PredicateName
        def self.lutaml_default_register
          :test_register
        end
        # rubocop:enable Naming/PredicateName

        attribute :name, :string
      end

      # String register should work
      instance = klass.new({}, register: :test_register)
      expect(instance.lutaml_register).to eq(:test_register)
    end

    it "lutaml_default_register returning nil uses Config.default_register" do
      klass = Class.new(Lutaml::Model::Serializable) do
        # rubocop:disable Naming/PredicateName
        def self.lutaml_default_register
          nil
        end
        # rubocop:enable Naming/PredicateName

        attribute :name, :string
      end

      instance = klass.new
      expect(instance.lutaml_register).to eq(:default)
    end

    it "false lutaml_default_register still falls back to Config" do
      klass = Class.new(Lutaml::Model::Serializable) do
        # rubocop:disable Naming/PredicateName
        def self.lutaml_default_register
          false
        end
        # rubocop:enable Naming/PredicateName

        attribute :name, :string
      end

      # false is falsy, so it should fall back to Config.default_register
      instance = klass.new
      expect(instance.lutaml_register).to eq(:default)
    end
  end
end
