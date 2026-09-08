# frozen_string_literal: true

require "spec_helper"

# A JSON::State reports every option including json's OWN defaults. Forwarding
# those to an adapter that reads a Hash overwrites its configuration: Oj treats
# an explicit ascii_only: false as a reason to reset escape_mode, which silently
# discards a configured XSS-safe boundary.
RSpec.describe "generator defaults not leaking into a hash-reading adapter" do
  before do
    require "oj"
    stub_const("EscapeProbe", Class.new(Lutaml::Model::Serializable) do
      attribute :s, :string
    end)
  end

  let(:model) { EscapeProbe.new(s: "</script>") }

  # json's own defaults must NOT be forwarded: an explicit ascii_only: false
  # makes Oj reset a configured escape_mode.
  it "does not overwrite the engine's own configuration with json defaults" do
    previous = Oj.default_options
    Oj.default_options = { escape_mode: :xss_safe }

    result = Lutaml::Model::Config.with_adapter(json: :oj) do
      JSON.generate({ "m" => model })
    end

    expect(result).to eq('{"m":{"s":"\\u003c\\/script\\u003e"}}')
  ensure
    Oj.default_options = previous
  end
end
