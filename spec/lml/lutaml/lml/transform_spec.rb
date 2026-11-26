# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Transform do
  let(:transform) { described_class.new }

  describe "visibility modifier rule" do
    it "converts '-' to 'private'" do
      result = transform.apply({ visibility_modifier: "-" })
      expect(result).to eq("private")
    end

    it "converts '#' to 'protected'" do
      result = transform.apply({ visibility_modifier: "#" })
      expect(result).to eq("protected")
    end

    it "converts '~' to 'package'" do
      result = transform.apply({ visibility_modifier: "~" })
      expect(result).to eq("package")
    end

    it "converts '+' to 'public'" do
      result = transform.apply({ visibility_modifier: "+" })
      expect(result).to eq("public")
    end
  end

  describe "simple member rule" do
    it "leaves scalar leaves verbatim" do
      result = transform.apply({ outer: "  hello  " })
      expect(result[:outer]).to eq("  hello  ")
    end
  end
end
