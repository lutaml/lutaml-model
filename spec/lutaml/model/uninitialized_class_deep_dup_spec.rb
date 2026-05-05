# frozen_string_literal: true

require "spec_helper"

RSpec.describe "UninitializedClass deep_dup compatibility" do
  let(:uninitialized) { Lutaml::Model::UninitializedClass.instance }

  # Replicates the rng gem's ExternalRefResolver#deep_dup pattern
  def deep_dup(obj)
    case obj
    when Array
      obj.map { |o| deep_dup(o) }
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[deep_dup(k)] = deep_dup(v) }
    when NilClass, Symbol, Numeric, TrueClass, FalseClass
      obj
    else
      obj.dup
    end
  end

  it "does not raise TypeError when deep_dup encounters UninitializedClass in a hash value" do
    data = { "key" => "value", "missing" => uninitialized }
    result = deep_dup(data)
    expect(result["missing"]).to equal(uninitialized)
  end

  it "does not raise TypeError when deep_dup encounters UninitializedClass in an array" do
    data = ["hello", uninitialized, "world"]
    result = deep_dup(data)
    expect(result[1]).to equal(uninitialized)
  end

  it "does not raise TypeError when deep_dup encounters UninitializedClass as hash key" do
    data = { uninitialized => "value" }
    result = deep_dup(data)
    expect(result.keys.first).to equal(uninitialized)
  end
end
