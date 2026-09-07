# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

# Regression spec for the XML accessor wiring of plain (non-Serialize)
# model classes declared via `model PlainClass`.
#
# The accessors are installed by
# FormatConversion#add_format_specific_model_methods, which must override
# the no-op base through Serialize::ClassMethods' prepend chain. Engines
# that do not propagate a prepend into an already-extended module to prior
# extenders' singleton chains (TruffleRuby —
# https://github.com/truffleruby/truffleruby/issues/4452) silently lose the
# override; this spec fails there without the format.rb re-prepend.
RSpec.describe "Plain model class XML accessors" do
  let(:plain_class) { Class.new }

  let(:wrapper_class) do
    pc = plain_class
    Class.new(Lutaml::Model::Serializable) do
      model pc

      xml do
        element "thing"
      end

      def self.name
        "PlainModelWrapper"
      end
    end
  end

  it "installs the XML accessors on the plain model class" do
    wrapper_class # force the `model` declaration

    %i[encoding encoding= doctype= element_order= ordered= mixed=
       xml_declaration= raw_schema_location=].each do |m|
      expect(plain_class.method_defined?(m)).to(be(true),
                                                "expected #{plain_class} to define ##{m}")
    end
  end

  it "parses XML into the plain model instance" do
    instance = wrapper_class.from_xml("<thing/>")

    expect(instance).to be_a(plain_class)
    expect(instance.element_order).not_to be_nil
  end
end
