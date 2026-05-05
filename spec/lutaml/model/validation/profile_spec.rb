# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"
require "tmpdir"
require "yaml"

RSpec.describe Lutaml::Model::Validation::Profile do
  let(:registry) { Lutaml::Model::Validation.new_registry }

  let(:profile) do
    described_class.new(
      name: "basic",
      description: "Basic checks",
      rule_names: ["TestRule"],
    )
  end

  it "stores profile attributes" do
    expect(profile.name).to eq("basic")
    expect(profile.description).to eq("Basic checks")
    expect(profile.rule_names).to eq(["TestRule"])
    expect(profile.imports).to eq([])
  end

  describe ".load" do
    it "loads profile from YAML file" do
      Dir.mktmpdir do |dir|
        yaml_path = File.join(dir, "basic.yml")
        File.write(yaml_path, YAML.dump({
                                          "name" => "loaded",
                                          "description" => "Loaded profile",
                                          "rules" => ["RuleA", "RuleB"],
                                          "import" => ["base"],
                                        }))
        loaded = described_class.load(yaml_path)
        expect(loaded.name).to eq("loaded")
        expect(loaded.rule_names).to eq(["RuleA", "RuleB"])
        expect(loaded.imports).to eq(["base"])
      end
    end
  end

  describe "#resolve" do
    context "with imports" do
      let(:base_rule_class) do
        Class.new(Lutaml::Model::Validation::Rule) do
          def self.name = "BaseRule"
          def code = "BASE-001"
        end
      end

      let(:extra_rule_class) do
        Class.new(Lutaml::Model::Validation::Rule) do
          def self.name = "ExtraRule"
          def code = "EXTRA-001"
        end
      end

      let(:base_profile) do
        described_class.new(name: "base", rule_names: ["BaseRule"])
      end

      let(:extended_profile) do
        described_class.new(
          name: "extended",
          rule_names: ["ExtraRule"],
          imports: ["base"],
        )
      end

      it "resolves imports" do
        registry.register(base_rule_class)
        registry.register(extra_rule_class)
        profiles = { "base" => base_profile, "extended" => extended_profile }

        rules = extended_profile.resolve(registry, profiles)
        codes = rules.map(&:code)
        expect(codes).to include("BASE-001", "EXTRA-001")
      end

      it "ignores missing imports" do
        registry.register(extra_rule_class)
        orphan = described_class.new(
          name: "orphan",
          rule_names: ["ExtraRule"],
          imports: ["nonexistent"],
        )
        rules = orphan.resolve(registry, {})
        expect(rules.map(&:code)).to eq(["EXTRA-001"])
      end
    end

    it "skips rules with unknown class names" do
      result = profile.resolve(registry)
      expect(result).to be_empty
    end
  end
end
