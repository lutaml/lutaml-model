# frozen_string_literal: true

# Opal-only boot for moxml.
#
# moxml's shipped `lib/compat/opal/moxml_boot.rb` (as of 0.1.25) requires
# the REXML adapter paths (`moxml/adapter/customized_rexml/*`,
# `moxml/adapter/rexml`), which in turn `require "rexml/formatters/pretty"`
# — a file that does not exist under Opal. Since lutaml-model targets Oga
# only under Opal, we mirror moxml's boot list with the REXML entries
# removed.
#
# If moxml fixes its boot file in a future release to gate the REXML
# requires, this file can be deleted and the Rakefile can switch back to
# `require "moxml_boot"`.

if RUBY_ENGINE == "opal"
  require "moxml/version"
  require "moxml/error"
  require "moxml/native_attachment"
  require "moxml/native_attachment/opal"
  require "moxml/xml_utils"
  require "moxml/xml_utils/encoder"
  require "moxml/node"
  require "moxml/node_set"
  require "moxml/document"
  require "moxml/element"
  require "moxml/attribute"
  require "moxml/text"
  require "moxml/cdata"
  require "moxml/comment"
  require "moxml/processing_instruction"
  require "moxml/declaration"
  require "moxml/namespace"
  require "moxml/doctype"
  require "moxml/entity_reference"
  require "moxml/entity_registry"
  require "moxml/adapter"
  require "moxml/adapter/base"
  # REXML adapter paths intentionally omitted — see file header.
  require "moxml/sax"
  require "moxml/sax/handler"
  require "moxml/sax/element_handler"
  require "moxml/sax/block_handler"
  require "moxml/sax/namespace_splitter"
  require "moxml/adapter/customized_oga"
  require "moxml/adapter/customized_oga/xml_declaration"
  require "moxml/adapter/customized_oga/xml_generator"
  require "moxml/adapter/oga"
  require "moxml/document_builder"
  require "moxml/builder"
  require "moxml/context"
  require "moxml/config"
  require "moxml/xpath"
  require "moxml/xpath/engine"
  require "moxml/xpath/context"
  require "moxml/xpath/conversion"
  require "moxml/xpath/cache"
  require "moxml/xpath/lexer"
  require "moxml/xpath/parser"
  require "moxml/xpath/compiler"
  require "moxml/xpath/errors"
  require "moxml/xpath/ast/node"
  require "moxml/xpath/ruby/node"
  require "moxml/xpath/ruby/generator"
end
