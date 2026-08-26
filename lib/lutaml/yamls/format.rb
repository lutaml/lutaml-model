# frozen_string_literal: true

# Internal YAMLS format implementation. Loaded from lib/lutaml/yamls.rb
# (the public entrypoint) and from lib/lutaml/model.rb (so the model
# entrypoint triggers the registration side effects).
# No require_relative "model" here — keeps the require graph acyclic.

module Lutaml
  module Yamls
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/adapter"
  end
end

Lutaml::Model::FormatRegistry.register(
  :yamls,
  mapping_class: Lutaml::Yamls::Adapter::Mapping,
  adapter_class: Lutaml::Yamls::Adapter::StandardAdapter,
  transformer: Lutaml::Yamls::Adapter::Transform,
  key_value: true,
)
