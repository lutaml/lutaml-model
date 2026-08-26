# frozen_string_literal: true

# Public Hash format entrypoint. Loads the base model and the internal
# implementation. The internal file does not require the model back,
# which keeps the require graph acyclic.
require_relative "model"
require_relative "hash_format/format"
