require "spec_helper"

RSpec.describe Lutaml::Model::Type do
  describe "Decimal type" do
    let(:decimal_class) { Lutaml::Model::Type::Decimal }

    context "when bigdecimal is loaded" do
      before do
        # Ensure BigDecimal is loaded
        require "bigdecimal"
      end

      it "serializes into Lutaml::Model::Type::Decimal" do
        value = BigDecimal("123.45")
        serialized = described_class.serialize(value, decimal_class)
        expect(serialized).to eq("123.45")
      end

      it "deserializes into Ruby BigDecimal" do
        value = "123.45"
        deserialized = described_class.cast(value, decimal_class)
        expect(deserialized).to be_a(BigDecimal)
        expect(deserialized).to eq(BigDecimal("123.45"))
      end
    end

    context "when bigdecimal is not loaded" do
      before do
        # Undefine BigDecimal if it exists
        Object.send(:remove_const, :BigDecimal) if defined?(BigDecimal)
        # Remove bigdecimal from $LOADED_FEATURES
        $LOADED_FEATURES.delete_if { |path| path.include?("bigdecimal") }
      end

      it "raises TypeNotEnabledError when serializing" do
        expect do
          described_class.serialize(123.45, decimal_class)
        end.to raise_error(Lutaml::Model::TypeNotEnabledError, /Decimal/)
      end

      it "raises TypeNotEnabledError when deserializing" do
        expect do
          described_class.cast("123.45", decimal_class)
        end.to raise_error(Lutaml::Model::TypeNotEnabledError, /Decimal/)
      end
    end
  end
end
