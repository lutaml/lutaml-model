# frozen_string_literal: true

module Lutaml
  module Lml
    # Non-serialized source metadata carried by parsed entities. These
    # accessors are deliberately not lutaml-model attributes: positions
    # and the source path are diagnostics metadata, not document data,
    # and must not appear in to_hash/YAML/JSON output.
    module Positioned
      attr_accessor :source_position, :source_path
    end
  end
end
