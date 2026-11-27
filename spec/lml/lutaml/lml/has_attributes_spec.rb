# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "parsanol"

# A real Struct-based host so we test the mixin against an object that
# owns its writers. Struct generates real writers, so behavior
# assertions don't depend on mocks.
HasAttributesHost = Struct.new(:name, :age, :type) do
  include Lutaml::Lml::HasAttributes
end

RSpec.describe Lutaml::Lml::HasAttributes do
  let(:host) { HasAttributesHost.new }

  describe "#update_attributes" do
    it "sets attributes from a hash with symbol keys" do
      host.update_attributes(name: "Alice", age: 30)
      expect(host.name).to eq("Alice")
      expect(host.age).to eq(30)
    end

    it "sets attributes from a hash with string keys" do
      host.update_attributes("name" => "Bob")
      expect(host.name).to eq("Bob")
    end

    it "unwraps Parsanol::Slice values into plain strings" do
      slice = Parsanol::Slice.new(0, "Carol", "source.lml")
      host.update_attributes(name: slice)
      expect(host.name).to eq("Carol")
      expect(host.name).to be_a(String)
    end

    it "handles empty input" do
      expect { host.update_attributes({}) }.not_to raise_error
      expect { host.update_attributes(nil) }.not_to raise_error
    end

    it "overwrites existing values" do
      host.update_attributes(name: "First")
      host.update_attributes(name: "Second")
      expect(host.name).to eq("Second")
    end

    it "preserves existing values for keys not in the input" do
      host.update_attributes(name: "Alice")
      host.update_attributes(age: 30)
      expect(host.name).to eq("Alice")
      expect(host.age).to eq(30)
    end
  end
end
