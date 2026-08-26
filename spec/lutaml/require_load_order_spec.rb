# frozen_string: true

require "spec_helper"

# lutaml-model: every public format entrypoint and `require "lutaml/model"`
# itself must not produce "circular require considered harmful" warnings
# under ruby -w (regression guard after the public-wrapper/internal-format
# restructuring).
RSpec.describe "require load order" do
  it "loads lutaml/model with no circular-require warnings under -w" do
    output = `bundle exec ruby -w -e 'require "lutaml/model"' 2>&1`
    circular = output.lines.count { |l| l.include?("circular require considered harmful") }
    expect(circular).to eq(0),
      "Expected no circular-require warnings, got #{circular}:\n#{output}"
  end

  %w[json key_value yaml toml hash_format jsonl yamls xml].each do |format|
    it "loads lutaml/#{format} standalone without circular-require warnings" do
      output = `bundle exec ruby -w -e 'require "lutaml/#{format}"' 2>&1`
      circular = output.lines.count { |l| l.include?("circular require considered harmful") }
      expect(circular).to eq(0),
        "Expected no circular-require warnings loading lutaml/#{format}, got #{circular}:\n#{output}"
    end
  end
end
