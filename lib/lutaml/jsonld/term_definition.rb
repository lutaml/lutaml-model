# frozen_string_literal: true

module Lutaml
  module JsonLd
    class TermDefinition
      attr_reader :name, :id, :type, :container, :language, :reverse

      def initialize(name:, id: nil, type: nil, container: nil, language: nil,
reverse: false)
        @name = name
        @id = id
        @type = type
        @container = container
        @language = language
        @reverse = reverse
      end

      def to_context_hash
        if simple_mapping?
          { @name => @id }
        else
          defn = {}
          defn["@id"] = @id if @id
          defn["@type"] = @type if @type
          defn["@container"] = "@#{@container}" if @container
          defn["@language"] = @language if @language
          defn["@reverse"] = @reverse if @reverse
          { @name => defn }
        end
      end

      private

      def simple_mapping?
        @id && @type.nil? && @container.nil? && @language.nil? && !@reverse
      end
    end
  end
end
