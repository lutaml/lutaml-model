# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::Schema::XsdSchema do
  # issue #1184: the xs:pattern expressibility probe is structural —
  # the constructs Ruby's engine adds beyond XSD 1.0's regexp are
  # detected syntactically, on every lane (a compile probe cannot
  # vouch where engines compile inexpressible patterns silently, and
  # lanes without a validator never probed at all).
  def probe(source)
    described_class.reject_invalid_xsd_pattern!(/#{Regexp.escape(source)}/x, source)
  end

  shared_examples "inexpressible" do |source, detail|
    it "rejects #{source.inspect}" do
      expect { probe(source) }
        .to raise_error(Lutaml::Model::Error, /not expressible.*#{detail}/)
    end
  end

  it_behaves_like "inexpressible", "(?=.*[0-9])[a-z]+", "lookaround"
  it_behaves_like "inexpressible", "a(?!b)", "lookaround"
  it_behaves_like "inexpressible", "(?<=a)b", "lookaround"
  it_behaves_like "inexpressible", "a(?>b|c)", "atomic"
  it_behaves_like "inexpressible", "a(?(1)b|c)", "conditional"
  it_behaves_like "inexpressible", "(a)\\1", "backreference"
  it_behaves_like "inexpressible", "(?<word>a)\\k<word>", "backreference"
  it_behaves_like "inexpressible", "a*+", "possessive quantifier"
  it_behaves_like "inexpressible", "a{2,3}+", "possessive quantifier"
  it_behaves_like "inexpressible", "a+?", "lazy quantifier"
  it_behaves_like "inexpressible", "a*??", "lazy quantifier"
  it_behaves_like "inexpressible", "\\Ga+", "anchor"

  it "admits plain groups and quantifiers" do
    expect { probe("[a-z]+(foo|bar)*baz?" ) }.not_to raise_error
  end

  it "does not false-positive on escapes or character classes" do
    expect { probe("\\[\\d\\]" ) }.not_to raise_error
    expect { probe("[a\\-z\\*+?]{2}" ) }.not_to raise_error
  end
end
