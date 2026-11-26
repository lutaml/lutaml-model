# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'models version declaration (issue #16)' do
  it 'captures the header version on the document' do
    doc = Lutaml::Lml.parse_document(StringIO.new(<<~LML))
      models PubidModels version "1.0.0" {
        class IsoIdentifier { }
      }
    LML
    expect(doc.model_versions).to eq('PubidModels' => '1.0.0')
  end

  it 'defaults to an empty version map without the declaration' do
    doc = Lutaml::Lml.parse_document(StringIO.new("models M {\n  class C { }\n}\n"))
    expect(doc.model_versions).to eq({})
  end

  it 'records each models block separately' do
    doc = Lutaml::Lml.parse_document(StringIO.new(<<~LML))
      models A version "1.0.0" { class C1 { } }
      models B version "2.0.0" { class C2 { } }
    LML
    expect(doc.model_versions).to eq('A' => '1.0.0', 'B' => '2.0.0')
  end
end
