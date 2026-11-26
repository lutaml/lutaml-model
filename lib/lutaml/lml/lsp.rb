# frozen_string_literal: true

module Lutaml
  module Lml
    # Language Server Protocol support: a stdio JSON-RPC server exposing
    # diagnostics, symbols, navigation, hover, completion, and canonical
    # formatting over the parsed document model.
    module Lsp
      autoload :Transport, "lutaml/lml/lsp/transport"
      autoload :Server, "lutaml/lml/lsp/server"
      autoload :Store, "lutaml/lml/lsp/store"
      autoload :Keywords, "lutaml/lml/lsp/keywords"
      autoload :Conversions, "lutaml/lml/lsp/conversions"
    end
  end
end
