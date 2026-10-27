# frozen_string_literal: true

require "spec_helper"

# A class that defines its own initialize is built through it by the
# from_* walk, and the walk hands it the register exactly as
# `new(lutaml_register:)` did before the compiled seed existed: a
# constructor that tells a blank construction from a caller's by that
# keyword sees the same call either way.
RSpec.describe "Walk construction of a custom-initialize class" do
  let(:model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      json do
        map "name", to: :name
      end

      class << self
        attr_accessor :constructions
      end

      def initialize(*args, **kwargs)
        self.class.constructions << [args, kwargs.keys]
        @internal = :ready
        super
      end

      attr_reader :internal
    end
  end

  before do
    stub_const("WalkConstructorModel", model)
    model.constructions = []
  end

  it "runs the class's own initialize" do
    expect(model.from_json('{"name":"a"}').internal).to eq(:ready)
  end

  it "passes the register, as the walk did through new(lutaml_register:)" do
    parsed = model.from_json('{"name":"a"}')

    expect(model.constructions).to eq([[[], [:lutaml_register]]])
    expect(parsed.name).to eq("a")
  end
end
