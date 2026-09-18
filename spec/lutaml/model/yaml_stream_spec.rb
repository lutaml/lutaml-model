# frozen_string_literal: true

require "spec_helper"

# lutaml-model#436: multi-document YAML streams with per-document model
# dispatch (the glossarist-ruby#132 / ISO 5843-6 shape).
RSpec.describe "YAML streams" do
  let(:concept_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :language_code, :string

      key_value do
        map "id", to: :id
        map "language_code", to: :language_code
      end
    end
  end

  let(:localized_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :status, :string

      key_value do
        map "id", to: :id
        map "status", to: :status
      end
    end
  end

  let(:stream) do
    <<~YAML
      ---
      id: 1-EN
      language_code: eng
      ---
      id: 3a75
      status: accepted
      ---
      id: 1-FR
      language_code: fra
    YAML
  end

  it "parses every document in the stream" do
    models = concept_class.from_yaml_stream(stream)
    expect(models.map(&:id)).to eq(%w[1-EN 3a75 1-FR])
  end

  it "dispatches documents polymorphically via discriminator" do
    models = concept_class.from_yaml_stream(
      stream,
      discriminator: lambda { |doc|
        doc.key?("language_code") ? concept_class : localized_class
      },
    )
    expect(models.map(&:class)).to eq([concept_class, localized_class,
                                       concept_class])
    expect(models[1].status).to eq("accepted")
  end

  it "round-trips through to_yaml_stream" do
    models = concept_class.from_yaml_stream(stream)
    out = concept_class.to_yaml_stream(models)
    reparsed = concept_class.from_yaml_stream(out)
    expect(reparsed.map(&:id)).to eq(models.map(&:id))
    expect(out).to include("---")
  end
end
