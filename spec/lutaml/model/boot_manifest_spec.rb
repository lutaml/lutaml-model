# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Guard: the generated Opal boot manifest must stay in sync with the autoloads
# in lib/lutaml/**. Opal ignores `autoload`, so lutaml_model_boot.rb explicitly
# requires every autoload target; a deleted/renamed file leaves a stale require
# that only fails the Opal CI job (`rake spec:opal`) — MRI's autoload hides it.
# Regenerating here and comparing catches that drift in the fast MRI suite.
RSpec.describe "Opal boot manifest" do
  let(:generator) do
    File.expand_path("../../../lib/compat/opal/generate_boot.rb", __dir__)
  end
  let(:manifest) do
    File.expand_path("../../../lib/compat/opal/lutaml_model_boot.rb", __dir__)
  end

  it "matches the generator output (regenerate: ruby lib/compat/opal/generate_boot.rb)" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "boot.rb")
      ok = system({ "OPAL_BOOT_OUTPUT" => out }, RbConfig.ruby, generator,
                  out: File::NULL, err: File::NULL)
      expect(ok).to be(true), "generate_boot.rb failed to run"
      expect(File.read(manifest)).to eq(File.read(out)),
                                     "lib/compat/opal/lutaml_model_boot.rb is out of date — run " \
                                     "`ruby lib/compat/opal/generate_boot.rb` after adding/removing autoloads"
    end
  end
end
