# frozen_string_literal: true

# Opal-only boot for moxml — mirrors moxml's shipped
# `lib/compat/opal/moxml_boot.rb` so both Oga and REXML adapters are
# eager-loaded (Opal ignores autoload; without this, nested Moxml
# constants NameError at runtime).
#
# Requires the REXML gem's lib dir to be on Opal's load path so
# `require "rexml/formatters/pretty"` (pulled in by moxml's
# customized_rexml/formatter) resolves. The Rakefile sets that up.
#
# moxml's own boot loads the same list. We maintain our own copy so we
# can reorder or gate entries if a future moxml release introduces an
# Opal-incompatible file before its shipped boot catches up.

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
  require "moxml/adapter/customized_rexml"
  require "moxml/adapter/customized_rexml/entity_reference"
  require "moxml/adapter/customized_rexml/formatter"
  require "moxml/sax"
  require "moxml/sax/handler"
  require "moxml/sax/element_handler"
  require "moxml/sax/block_handler"
  require "moxml/sax/namespace_splitter"
  require "moxml/adapter/rexml"
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
