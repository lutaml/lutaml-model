require "spec_helper"

# Regression: Transform#apply_value_map must handle the nil-attr case used
# by custom-method-only key-value rules. Pre-consolidation behavior:
# the default { omitted: :nil, nil: :nil, empty: :empty } map converted
# UninitializedClass.instance to nil so the downstream Utils.present? guard
# in KeyValue::Transform#process_mapping_rule would skip the custom method
# for absent input keys.
RSpec.describe Lutaml::Model::Transform, "#apply_value_map (nil attr)" do
  let(:transform_subclass) do
    Class.new(described_class) do
      # Expose the protected delegator for direct testing.
      public :apply_value_map
    end
  end

  let(:context) { Class.new(Lutaml::Model::Serializable) }
  let(:register) { Lutaml::Model::Config.default_register }
  let(:transform) { transform_subclass.new(context, register) }

  let(:uninit) { Lutaml::Model::UninitializedClass.instance }
  let(:default_vmap) { { omitted: :nil, nil: :nil, empty: :empty } }

  describe "default mapping with nil attr" do
    it "converts UninitializedClass to nil via the :omitted => :nil mapping" do
      # Before the fix: returned uninit unchanged, causing Utils.present? to
      # be true and the custom method to run for absent fields.
      expect(transform.apply_value_map(uninit, default_vmap, nil)).to be_nil
    end

    it "converts nil to nil via the :nil => :nil mapping" do
      expect(transform.apply_value_map(nil, default_vmap, nil)).to be_nil
    end

    it "passes initialized values through unchanged" do
      expect(transform.apply_value_map("hello", default_vmap, nil)).to eq("hello")
    end
  end

  describe "explicit :omitted => :omitted with nil attr" do
    let(:vmap) { { omitted: :omitted, nil: :nil, empty: :empty } }

    it "preserves UninitializedClass for explicit omitted: :omitted" do
      expect(transform.apply_value_map(uninit, vmap, nil)).to eq(uninit)
    end
  end
end
