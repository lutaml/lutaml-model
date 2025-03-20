# lutaml-model Release Notes: v0.6.7 to v0.7.1

## Overview

This release introduces significant enhancements to the lutaml-model library, focusing on improved handling of missing values, comprehensive polymorphic model support, and important bug fixes. This document outlines the key changes and provides guidance for upgrading your codebase.

## Key Changes

### 1. Missing Values Handling Family

A comprehensive set of features for handling the "missing values" family (empty, non-existent, and undefined values) across different serialization formats has been introduced.

#### 1.1 `value_map` Option

The `value_map` option provides fine-grained control over how missing values are handled during serialization and deserialization. This is especially useful when different serialization formats represent missing values differently.

```ruby
class ExampleClass < Lutaml::Model::Serializable
  attribute :status, :string

  xml do
    map_element 'status', to: :status, value_map: {
      from: { empty: :nil, omitted: :omitted, nil: :nil },
      to: { empty: :nil, omitted: :omitted, nil: :nil }
    }
  end

  json do
    map 'status', to: :status, value_map: {
      from: { empty: :nil, omitted: :omitted, nil: :nil },
      to: { empty: :nil, omitted: :omitted, nil: :nil }
    }
  end

  toml do
    map 'status', to: :status, value_map: {
      from: { empty: :nil, omitted: :omitted },
      to: { empty: :nil, omitted: :omitted, nil: :omitted }
    }
  end
end
```

For collection attributes, the value_map behaves differently depending on the `initialize_empty` setting.

#### 1.2 `initialize_empty` Option

The `initialize_empty` option controls the default initialization behavior of collection attributes:

```ruby
# Default to `nil`
class SomeModel < Lutaml::Model::Serializable
  attribute :coll, :string, collection: true

  xml do
    root "some-model"
    map_element 'collection', to: :coll
  end
end
puts SomeModel.new.coll  # => nil

# Default to empty array
class SomeModel < Lutaml::Model::Serializable
  attribute :coll, :string, collection: true, initialize_empty: true

  xml do
    map_element 'collection', to: :coll
  end
end
puts SomeModel.new.coll  # => []
```

#### 1.3 `render_nil` and `render_empty` Modes

These options provide shorthand methods to control how nil and empty values are rendered in serialization formats:

- `render_nil: true | :as_empty | :as_blank | :nil | :omit` - Controls how nil values are rendered
- `render_empty: :as_empty | :as_blank | :nil | :omit` - Controls how empty collections are rendered

```ruby
class SomeModel < Lutaml::Model::Serializable
  attribute :coll, :string, collection: true

  xml do
    root "some-model"
    map_element 'collection', to: :coll, render_nil: :omit
  end

  json do
    map 'collection', to: :coll, render_empty: :as_nil
  end
end
```

### 2. Polymorphic Model Support

Comprehensive support for polymorphic models has been introduced, allowing for flexible modeling of inheritance relationships and proper serialization/deserialization.

#### 2.1 Polymorphic Attribute Definition

Polymorphic attributes can be defined using the `polymorphic` option:

```ruby
class ReferenceSet < Lutaml::Model::Serializable
  attribute :references, Reference, collection: true, polymorphic: [
    DocumentReference,
    AnchorReference,
  ]
end
```

#### 2.2 Polymorphic Class Differentiator

A polymorphic differentiator attribute can be set in either the superclass or subclasses:

```ruby
# In superclass
class Reference < Lutaml::Model::Serializable
  attribute :_class, :string, polymorphic_class: true
  # ...
end

# Or in subclasses
class DocumentReference < Reference
  attribute :_class, :string, polymorphic_class: true
  # ...
end
```

#### 2.3 Serialization Support

Polymorphic mapping in serialization is supported through the `polymorphic_map` option:

```ruby
class Reference < Lutaml::Model::Serializable
  attribute :_class, :string, polymorphic_class: true
  
  xml do
    map_attribute "reference-type", to: :_class, polymorphic_map: {
      "document-ref" => "DocumentReference",
      "anchor-ref" => "AnchorReference"
    }
  end
  
  key_value do
    map "_class", to: :_class, polymorphic_map: {
      "Document" => "DocumentReference",
      "Anchor" => "AnchorReference"
    }
  end
end
```

### 3. Importable Model Improvements

Importable model functionality has been improved, with better support for reusable models:

- `import_model` - Imports both attributes and mappings
- `import_model_attributes` - Imports only attributes
- `import_model_mappings` - Imports only mappings

Bug fixes for the import_model functionality ensure more reliable model reuse.

### 4. Circular Reference Handling

Improved handling of circular references in the `ComparableModel` module prevents stack overflow errors when comparing models with self-referential structures.

## Upgrade Guide

### Missing Values Handling

If you were previously using `render_nil: true`, you can continue using it, but you may want to explore the more flexible `value_map` option for fine-grained control over different serialization formats.

For collection attributes, consider whether you want collections to initialize as `nil` or as an empty array by setting the `initialize_empty` option accordingly.

### Polymorphic Models

If you were previously using class detection for polymorphic models without explicit differentiators, you should now define a polymorphic differentiator attribute and use the `polymorphic_class: true` option.

## Contributors

Thank you to all contributors who made this release possible, especially:
- HassanAkbar
- Ronald Tse
- suleman-uzair

## Compatibility

This release maintains compatibility with Ruby 2.7 and above.