# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::RuntimeCompatibility do
  describe ".opal?" do
    it "memoizes false results on native Ruby" do
      skip "native-only memoization example" if RUBY_ENGINE == "opal"

      described_class.remove_instance_variable(:@opal) if described_class.instance_variable_defined?(:@opal)

      expect(described_class.opal?).to be(false)
      expect(described_class.instance_variable_defined?(:@opal)).to be(true)
      expect(described_class.instance_variable_get(:@opal)).to be(false)
    end
  end

  describe ".safe_constantize" do
    it "returns nil when the top-level constant is missing" do
      expect(described_class.safe_constantize("MissingTopLevel::Error")).to be_nil
    end

    it "matches Ruby constant lookup through inherited namespaces" do
      parent = Class.new
      error_class = Class.new(StandardError)
      parent.const_set(:InheritedError, error_class)
      child = Class.new(parent)

      stub_const("RuntimeCompatibilityParent", parent)
      stub_const("RuntimeCompatibilityChild", child)

      expect(described_class.safe_constantize("RuntimeCompatibilityChild::InheritedError"))
        .to eq(error_class)
    end
  end
end
