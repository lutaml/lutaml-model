# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"
require "lutaml/lml/executor"

RSpec.describe Lutaml::Lml::Executor::FormatAdapter do
  describe ".register and .resolve" do
    it "registers and resolves an adapter" do
      adapter = Class.new
      described_class.register("test_format", adapter)
      expect(described_class.resolve("test_format")).to eq(adapter)
    end

    it "raises AdapterNotFoundError for unknown formats" do
      expect { described_class.resolve("nonexistent") }
        .to raise_error(described_class::AdapterNotFoundError)
    end

    it "lists registered formats" do
      described_class.resolve("csv")
      described_class.resolve("xml")
      expect(described_class.registered_formats).to include("csv", "xml")
    end

    it "resolves builtin adapters via lazy autoload" do
      expect(described_class.resolve("csv")).to eq(Lutaml::Lml::Executor::CsvAdapter)
      expect(described_class.resolve("xml")).to eq(Lutaml::Lml::Executor::XmlAdapter)
    end
  end
end
