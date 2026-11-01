# frozen_string_literal: true

# Opal doesn't support Ruby autoload: this boot explicitly requires
# every top-level Moxml module that lib/moxml.rb declares via
# autoload. Generated from the moxml 0.6 module table (the 0.5-line
# boot shipped inside moxml's lib/compat/opal and named 0.5-era paths,
# including moxml/native_attachment/opal, which the 0.6 line drops).
# Loaded by the Opal Rakefile before spec_helper; regenerate against
# a new moxml line by re-listing its top-level lib/moxml/*.rb files.
require "moxml/version"

require "moxml/adapter"
require "moxml/attribute"
require "moxml/attribute_resolver"
require "moxml/builder"
require "moxml/c14n"
require "moxml/cdata"
require "moxml/comment"
require "moxml/config"
require "moxml/context"
require "moxml/css"
require "moxml/declaration"
require "moxml/doctype"
require "moxml/document"
require "moxml/document_builder"
require "moxml/element"
require "moxml/entity"
require "moxml/entity_reference"
require "moxml/entity_registry"
require "moxml/error"
require "moxml/html_fragment"
require "moxml/lazy_bulk_rows"
require "moxml/lazy_node_set"
require "moxml/materializer"
require "moxml/namespace"
require "moxml/native_attachment"
require "moxml/node"
require "moxml/node_set"
require "moxml/plan"
require "moxml/processing_instruction"
require "moxml/reference"
require "moxml/relaxng"
require "moxml/sax"
require "moxml/signature"
require "moxml/struct_plan"
require "moxml/text"
require "moxml/wrappers"
require "moxml/xml_emitter"
require "moxml/xml_utils"
require "moxml/xpath"
require "moxml/xsd"
require "moxml/xslt"
