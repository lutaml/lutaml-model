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

  # lib/lutaml/model.rb and lib/lutaml/xml.rb re-evaluate their top-level
  # prepend calls when Opal's eager loader processes them more than once.
  # Opal's Module#prepend raises "Prepending a module multiple times is
  # not supported" in that case; runtime_compatibility.rb aligns Opal
  # with MRI's idempotent behavior. MRI has been idempotent since 2.0,
  # so the spec applies to both runtimes.
  describe "Module#prepend idempotency" do
    it "is a no-op when the module is already in the ancestor chain" do
      mod = Module.new
      klass = Class.new
      klass.prepend(mod)

      expect { klass.prepend(mod) }.not_to raise_error
      expect(klass.ancestors.count(mod)).to eq(1)
    end

    it "still prepends when the module is not yet present" do
      mod = Module.new
      klass = Class.new

      expect { klass.prepend(mod) }.not_to raise_error
      expect(klass.ancestors).to include(mod)
    end
  end
end
