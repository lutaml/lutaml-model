require_relative "../../lib/lutaml/model"

module GeolexicaV2
  # --- Leaf types ---

  class ContentBlock < Lutaml::Model::Serializable
    attribute :content, :string

    yaml do
      map "content", to: :content
    end
  end

  class TermDesignation < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :normative_status, :string
    attribute :designation, :string

    yaml do
      map "type", to: :type
      map "normative_status", to: :normative_status
      map "designation", to: :designation
    end
  end

  class Locality < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :reference_from, :string

    yaml do
      map "type", to: :type
      map "reference_from", to: :reference_from
    end
  end

  class SourceOrigin < Lutaml::Model::Serializable
    attribute :ref, :string
    attribute :locality, Locality
    attribute :link, :string

    yaml do
      map "ref", to: :ref
      map "locality", to: :locality
      map "link", to: :link
    end
  end

  class Source < Lutaml::Model::Serializable
    attribute :origin, SourceOrigin
    attribute :type, :string

    yaml do
      map "origin", to: :origin
      map "type", to: :type
    end
  end

  # --- Document 0: Concept Index ---

  class ConceptIndexData < Lutaml::Model::Serializable
    attribute :identifier, :string
    attribute :localized_concepts, :hash

    yaml do
      map "identifier", to: :identifier
      map "localized_concepts", to: :localized_concepts
    end
  end

  class ConceptIndex < Lutaml::Model::Serializable
    attribute :data, ConceptIndexData
    attribute :id, :string

    yaml do
      map "data", to: :data
      map "id", to: :id
    end
  end

  # --- Document 1: Localized Concept ---

  class LocalizedConceptData < Lutaml::Model::Serializable
    attribute :definition, ContentBlock, collection: true
    attribute :examples, ContentBlock, collection: true
    attribute :notes, ContentBlock, collection: true
    attribute :sources, Source, collection: true
    attribute :terms, TermDesignation, collection: true
    attribute :language_code, :string
    attribute :entry_status, :string

    yaml do
      map "definition", to: :definition, render_empty: true
      map "examples", to: :examples, render_empty: true
      map "notes", to: :notes, render_empty: true
      map "sources", to: :sources, render_empty: true
      map "terms", to: :terms
      map "language_code", to: :language_code
      map "entry_status", to: :entry_status
    end
  end

  class LocalizedConcept < Lutaml::Model::Serializable
    attribute :data, LocalizedConceptData
    attribute :id, :string

    yaml do
      map "data", to: :data
      map "id", to: :id
    end
  end

  # --- Managed Concept: YAMLS sequence of ConceptIndex + LocalizedConcept ---

  class ManagedConcept < Lutaml::Model::Serializable
    attribute :index, ConceptIndex
    attribute :localized, LocalizedConcept, collection: true

    yamls do
      sequence do
        map_document 0, to: :index, type: ConceptIndex
        map_document 1.., to: :localized, type: LocalizedConcept,
                          collection: true
      end
    end
  end

  # --- Collection of ManagedConcepts (directory of v2 files) ---

  class ManagedConceptCollection < Lutaml::Model::Collection
    instances :concepts, ManagedConcept

    yamls do
      map_instances to: :concepts
    end
  end
end
