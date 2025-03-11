module CustomBibtexAdapterSpec
  class BibtexAdapter < Lutaml::Model::SerializationAdapter
    handles_format :bibtex
    document_class BibtexDocument

    def initialize(document)
      @document = document
    end

    def to_bibtex(*)
      @document.to_bibtex
    end
  end
end
