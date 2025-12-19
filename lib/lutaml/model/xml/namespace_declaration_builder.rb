# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # NamespaceDeclarationBuilder - Build xmlns attributes from DeclarationPlan
      #
      # EXTRACTED FROM: Phase 3A of adapter refactoring
      # SOURCE: nokogiri_adapter.rb:170-188, oga_adapter.rb:172-190, ox_adapter.rb:112-130
      #
      # PURPOSE:
      # Converts namespace declarations from a DeclarationPlan into xmlns attributes
      # for XML element construction.
      #
      # RESPONSIBILITIES:
      # - Iterate through plan.declarations_here
      # - Skip implicitly bound xml namespace
      # - Parse xmlns declaration strings
      # - Build attributes hash with xmlns declarations
      #
      # USAGE:
      #   attributes = NamespaceDeclarationBuilder.build_xmlns_attributes(plan)
      #
      module NamespaceDeclarationBuilder
        # Build xmlns attributes from namespace declarations in plan
        #
        # @param plan [DeclarationPlan] the declaration plan with namespace info
        # @return [Hash] attributes hash with xmlns declarations
        def self.build_xmlns_attributes(plan)
          attributes = {}

          # Apply namespace declarations from plan
          plan.declarations_here.each_value do |ns_decl|
            ns_class = ns_decl.ns_object

            # CRITICAL: Never declare xml namespace - it's implicitly bound
            # Per https://www.w3.org/XML/1998/namespace, the xml prefix is
            # reserved and MUST NOT be declared with xmlns:xml
            next if ns_class.uri == "http://www.w3.org/XML/1998/namespace"

            # Parse the ready-to-use declaration string
            decl = ns_decl.xmlns_declaration
            if decl.start_with?("xmlns:")
              # Prefixed namespace: "xmlns:prefix=\"uri\""
              prefix = decl[/xmlns:(\w+)=/, 1]
              attributes["xmlns:#{prefix}"] = ns_class.uri
            else
              # Default namespace: "xmlns=\"uri\""
              attributes["xmlns"] = ns_class.uri
            end
          end

          attributes
        end
      end
    end
  end
end