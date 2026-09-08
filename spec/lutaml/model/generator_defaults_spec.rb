# frozen_string_literal: true

require "spec_helper"
require "oj"
require "multi_json"

# What a nested model should do with the outer generator's options differs per
# ADAPTER, not per option. Reference values are unmodified main on json 2.21.2.
#
#   stdlib  honours script_safe / ascii_only / pretty  -> receives the state
#   Oj      ignores them and uses its own escape_mode  -> receives none of them
#
# Four earlier attempts at this got it wrong by reasoning about option names
# instead of measuring each adapter, so every row here is a measured cell.
RSpec.describe "generator options reaching a nested model" do
  before do
    stub_const("EscapeProbe", Class.new(Lutaml::Model::Serializable) do
      attribute :s, :string
    end)
  end

  let(:model) { EscapeProbe.new(s: "</script>é") }

  describe "the stdlib adapter" do
    it "honours script_safe" do
      expect(JSON.generate({ "m" => model }, script_safe: true))
        .to eq('{"m":{"s":"<\\/script>é"}}')
    end

    it "honours ascii_only" do
      expect(JSON.generate({ "m" => model }, ascii_only: true))
        .to eq('{"m":{"s":"</script>\\u00e9"}}')
    end

    it "honours the outer indent" do
      expect(JSON.pretty_generate({ "m" => model }))
        .to eq(%({\n  "m": {\n    "s": "</script>é"\n  }\n}))
    end
  end

  describe "the Oj adapter" do
    around do |example|
      previous = Oj.default_options
      Oj.default_options = { escape_mode: :xss_safe }
      example.run
      Oj.default_options = previous
    end

    # Oj must keep its OWN escaping. Forwarding the generator's options -- all
    # of them, only the caller-set ones, or just ascii_only -- each reset
    # escape_mode and silently emitted a literal </script>.
    it "keeps its configured escape_mode when no option is passed" do
      result = Lutaml::Model::Config.with_adapter(json: :oj) do
        JSON.generate({ "m" => model })
      end

      expect(result).to eq('{"m":{"s":"\\u003c\\/script\\u003e\\u00e9"}}')
    end

    it "keeps its configured escape_mode when ascii_only is passed" do
      result = Lutaml::Model::Config.with_adapter(json: :oj) do
        JSON.generate({ "m" => model }, ascii_only: true)
      end

      expect(result).to eq('{"m":{"s":"\\u003c\\/script\\u003e\\u00e9"}}')
    end

    it "keeps its configured escape_mode when script_safe is passed" do
      result = Lutaml::Model::Config.with_adapter(json: :oj) do
        JSON.generate({ "m" => model }, script_safe: true)
      end

      expect(result).to eq('{"m":{"s":"\\u003c\\/script\\u003e\\u00e9"}}')
    end
  end

  # MultiJson's json_gem backend IS the stdlib generator, so unlike Oj it does
  # honour these options and must still receive them. multi_json 1.21.1 cannot
  # run at all under json 3.0 (it sends create_additions, which json removed),
  # so this is asserted on the versions where the adapter works.
  describe "the MultiJson adapter", if: Gem::Version.new(JSON::VERSION) < Gem::Version.new("3.0.0") do
    before { MultiJson.use(:json_gem) }

    it "still receives script_safe" do
      result = Lutaml::Model::Config.with_adapter(json: :multi_json) do
        JSON.generate({ "m" => model }, script_safe: true)
      end

      expect(result).to eq('{"m":{"s":"<\\/script>é"}}')
    end

    it "still receives ascii_only" do
      result = Lutaml::Model::Config.with_adapter(json: :multi_json) do
        JSON.generate({ "m" => model }, ascii_only: true)
      end

      expect(result).to eq('{"m":{"s":"</script>\\u00e9"}}')
    end
  end
end
