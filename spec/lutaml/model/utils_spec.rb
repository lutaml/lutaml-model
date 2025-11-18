require "spec_helper"
require "lutaml/model/utils"

CAMEL_CASE_EXAMPLES = {
  "hello_world" => "HelloWorld",
  "foo_bar_baz" => "FooBarBaz",
  "" => "",
  nil => "",
  "hello_world/foo_bar_baz" => "HelloWorld::FooBarBaz",
}.freeze

CLASSIFY_EXAMPLES = CAMEL_CASE_EXAMPLES.merge({
                                                "hello_world::foo_bar_baz" => "HelloWorld::FooBarBaz",
                                              }).freeze

SNAKE_CASE_EXAMPLES = {
  "HelloWorld" => "hello_world",
  "FooBarBaz" => "foo_bar_baz",
  "" => "",
  nil => "",
  "HelloWorld::FooBarBaz" => "hello_world/foo_bar_baz",
}.freeze

RSpec.describe Lutaml::Model::Utils do
  let(:utils) { described_class }

  shared_examples "string conversion" do |method, examples|
    describe ".#{method}" do
      examples.each do |input, expected_output|
        context "when input is #{input.nil? ? 'nil' : "'#{input}'"}" do
          it "returns '#{expected_output}'" do
            expect(utils.send(method, input)).to eq(expected_output)
          end
        end
      end
    end
  end

  it_behaves_like "string conversion", :camel_case, CAMEL_CASE_EXAMPLES
  it_behaves_like "string conversion", :classify, CLASSIFY_EXAMPLES
  it_behaves_like "string conversion", :snake_case, SNAKE_CASE_EXAMPLES

  describe ".deep_dup" do
    let(:original_hash) do
      {
        one: {
          one_one: {
            one_one1: "one",
            one_one2: :two,
          },
          one_two: "12",
        },
      }
    end

    let(:original_array) do
      [
        "one", [
          "one_one", [
            "one_one1", "one_one2"
          ],
          "one_two"
        ]
      ]
    end

    let(:duplicate_hash) { utils.deep_dup(original_hash) }
    let(:duplicate_array) { utils.deep_dup(original_array) }

    it "creates deep duplicate of hash" do
      expect(compare_duplicate(original_hash, duplicate_hash)).to be_truthy
    end

    it "creates a deep duplicate of the array" do
      expect(compare_duplicate(original_array, duplicate_array)).to be_truthy
    end

    def compare_duplicate(original, duplicate)
      return false unless original == duplicate
      return false if !primitive?(original) && original.equal?(duplicate)

      case original
      when Array then compare_array(original, duplicate)
      when Hash then compare_hash(original, duplicate)
      else true
      end
    end

    def compare_array(original, duplicate)
      original.each_with_index.all? do |el, i|
        compare_duplicate(el, duplicate[i])
      end
    end

    def compare_hash(original, duplicate)
      original.keys.all? do |key|
        compare_duplicate(original[key], duplicate[key])
      end
    end

    def primitive?(value)
      [Symbol, NilClass, TrueClass, FalseClass].include?(value.class)
    end
  end
end
