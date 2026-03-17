# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/toml"

RSpec.describe Lutaml::Model::Toml do
  describe ".detect_toml_adapter" do
    before do
      # Hide any existing constants first
      hide_const("Tomlib") if Object.const_defined?(:Tomlib)
      hide_const("TomlRb") if Object.const_defined?(:TomlRb)

      # Stub require to prevent any actual requires during testing
      allow(Lutaml::Model::Utils).to receive(:require).and_return(true)
    end

    context "when Tomlib is available" do
      before do
        stub_const("Tomlib", Module.new)
      end

      it "returns :tomlib on non-Windows platforms" do
        allow(Gem).to receive(:win_platform?).and_return(false)
        expect(described_class.detect_toml_adapter).to eq(:tomlib)
      end

      it "returns :toml_rb on Windows (skips tomlib due to segfaults)" do
        allow(Gem).to receive(:win_platform?).and_return(true)
        stub_const("TomlRb", Module.new)
        expect(described_class.detect_toml_adapter).to eq(:toml_rb)
      end
    end

    context "when TomlRb is available" do
      before do
        stub_const("TomlRb", Module.new)
      end

      it "returns :toml_rb" do
        expect(described_class.detect_toml_adapter).to eq(:toml_rb)
      end
    end

    context "when neither adapter is available" do
      it "returns nil" do
        expect(described_class.detect_toml_adapter).to be_nil
      end
    end

    context "when both adapters are available" do
      before do
        stub_const("Tomlib", Module.new)
        stub_const("TomlRb", Module.new)
      end

      it "prefers Tomlib on non-Windows platforms" do
        allow(Gem).to receive(:win_platform?).and_return(false)
        expect(described_class.detect_toml_adapter).to eq(:tomlib)
      end

      it "prefers TomlRb on Windows (skips tomlib due to segfaults)" do
        allow(Gem).to receive(:win_platform?).and_return(true)
        expect(described_class.detect_toml_adapter).to eq(:toml_rb)
      end
    end
  end
end
