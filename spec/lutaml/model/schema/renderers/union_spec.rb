# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema/definitions"
require "lutaml/model/schema/renderers/union"

RSpec.describe Lutaml::Model::Schema::Renderers::Union do
  let(:defs) { Lutaml::Model::Schema::Definitions }

  it "renders the :class_refs strategy as an each/begin/rescue loop" do
    spec = defs::UnionType.new(
      class_name: "NumberOrString",
      members: [
        defs::TypeRef.new(kind: :class_ref, value: "Integer"),
        defs::TypeRef.new(kind: :class_ref, value: "String"),
      ],
      cast_strategy: :class_refs,
    )

    output = described_class.render(spec)

    expect(output).to include("class NumberOrString < Lutaml::Model::Type::Value")
    expect(output).to include("[Integer, String].each do |t|")
    expect(output).to include("casted = t.cast(value, options)")
    expect(output).to include("return casted unless casted.nil?")
    expect(output).to include("rescue StandardError")
  end

  it "renders the :resolve_type strategy as a ||-chained resolve_type call" do
    spec = defs::UnionType.new(
      class_name: "IntegerOrToken",
      members: [
        defs::TypeRef.new(kind: :symbol, value: "integer"),
        defs::TypeRef.new(kind: :symbol, value: "token"),
      ],
      cast_strategy: :resolve_type,
    )

    output = described_class.render(spec)

    expect(output).to include("Lutaml::Model::GlobalContext.resolve_type(:integer, @register).cast(value, options)")
    expect(output).to include("Lutaml::Model::GlobalContext.resolve_type(:token, @register).cast(value, options)")
    expect(output).to include(" ||\n")
  end

  it "emits required_files lines above the module wrap" do
    spec = defs::UnionType.new(
      class_name: "AnyOf",
      members: [defs::TypeRef.new(kind: :class_ref, value: "Integer")],
      cast_strategy: :class_refs,
      required_files: ['require_relative "integer"'],
    )

    output = described_class.render(spec)

    expect(output).to include('require_relative "integer"')
  end
end
