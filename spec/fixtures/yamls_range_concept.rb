require_relative "../../lib/lutaml/model"

module YamlsRangeTest
  class Header < Lutaml::Model::Serializable
    attribute :title, :string
    attribute :version, :integer

    yaml do
      map "title", to: :title
      map "version", to: :version
    end
  end

  class Metadata < Lutaml::Model::Serializable
    attribute :author, :string
    attribute :date, :string

    yaml do
      map "author", to: :author
      map "date", to: :date
    end
  end

  class Entry < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, :string

    yaml do
      map "name", to: :name
      map "value", to: :value
    end
  end

  class Footer < Lutaml::Model::Serializable
    attribute :note, :string

    yaml do
      map "note", to: :note
    end
  end

  # Uses various range patterns: 0..1, 2..3, -1, etc.
  class Document < Lutaml::Model::Serializable
    attribute :headers, Header, collection: true
    attribute :entries, Entry, collection: true
    attribute :footer, Footer

    yamls do
      sequence do
        map_document 0..1, to: :headers, type: Header, collection: true
        map_document 2..3, to: :entries, type: Entry, collection: true
        map_document -1, to: :footer, type: Footer
      end
    end
  end

  # Uses negative ranges: -2..-1 for the last 2 docs
  class DocumentNegRange < Lutaml::Model::Serializable
    attribute :headers, Header, collection: true
    attribute :trailers, Entry, collection: true

    yamls do
      sequence do
        map_document 0..1, to: :headers, type: Header, collection: true
        map_document -2..-1, to: :trailers, type: Entry, collection: true
      end
    end
  end

  # Uses 2..-1 to capture from position 2 to end
  class DocumentOpenRange < Lutaml::Model::Serializable
    attribute :header, Header
    attribute :rest, Entry, collection: true

    yamls do
      sequence do
        map_document 0, to: :header, type: Header
        map_document 1..-1, to: :rest, type: Entry, collection: true
      end
    end
  end

  # Uses -1 for last doc as a collection
  class DocumentLastOnly < Lutaml::Model::Serializable
    attribute :last_entry, Entry

    yamls do
      sequence do
        map_document -1, to: :last_entry, type: Entry
      end
    end
  end

  # 3 ranges with 3 different types:
  #   0..1 → Headers (flex range in front), 2..3 → Metadata, -2..-1 → Footers (flex range at back)
  class ThreeRangesFrontFlex < Lutaml::Model::Serializable
    attribute :headers, Header, collection: true
    attribute :metas, Metadata, collection: true
    attribute :trailers, Entry, collection: true

    yamls do
      sequence do
        map_document 0..1, to: :headers, type: Header, collection: true
        map_document 2..3, to: :metas, type: Metadata, collection: true
        map_document -2..-1, to: :trailers, type: Entry, collection: true
      end
    end
  end

  # 3 ranges: 0 (single Header), 1..3 (Metadata collection), -1 (single Footer)
  class ThreeRangesMixed < Lutaml::Model::Serializable
    attribute :header, Header
    attribute :metas, Metadata, collection: true
    attribute :footer, Footer

    yamls do
      sequence do
        map_document 0, to: :header, type: Header
        map_document 1..3, to: :metas, type: Metadata, collection: true
        map_document -1, to: :footer, type: Footer
      end
    end
  end

  # 3 ranges: 0..1 (Headers), -3..-2 (Entries), -1 (Footer)
  class ThreeRangesNegMiddle < Lutaml::Model::Serializable
    attribute :headers, Header, collection: true
    attribute :entries, Entry, collection: true
    attribute :footer, Footer

    yamls do
      sequence do
        map_document 0..1, to: :headers, type: Header, collection: true
        map_document -3..-2, to: :entries, type: Entry, collection: true
        map_document -1, to: :footer, type: Footer
      end
    end
  end
end
