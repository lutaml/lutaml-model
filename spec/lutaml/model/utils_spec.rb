require "spec_helper"
require "lutaml/model/utils"

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

  camel_case_examples = {
    "hello_world" => "HelloWorld",
    "foo_bar_baz" => "FooBarBaz",
    "" => "",
    nil => "",
    "hello_world/foo_bar_baz" => "HelloWorld::FooBarBaz",
  }

  classify_examples_extra = {
    "hello_world::foo_bar_baz" => "HelloWorld::FooBarBaz",
  }
  classify_examples = camel_case_examples.merge(classify_examples_extra)

  snake_case_examples = {
    "HelloWorld" => "hello_world",
    "FooBarBaz" => "foo_bar_baz",
    "" => "",
    nil => "",
    "HelloWorld::FooBarBaz" => "hello_world/foo_bar_baz",
  }

  include_examples "string conversion", :camel_case, camel_case_examples
  include_examples "string conversion", :classify, classify_examples
  include_examples "string conversion", :snake_case, snake_case_examples
end
