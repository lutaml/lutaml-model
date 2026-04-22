# Bug Report: render_empty: :as_blank not respected in element_order serialization

## Status: FIXED

This bug has been resolved. The ordered applier now correctly handles empty
collections with `render_empty: :as_blank` and `render_empty: :as_nil`.
See `spec/lutaml/model/render_empty_spec.rb:248` for the test coverage.

## Original Report

### Summary

When `render_empty: :as_blank` is set on a collection element mapping, empty collections should be serialized as self-closing XML elements (e.g., `<topic/>`). However, this only works when the model was **not** parsed from XML. Models parsed from XML have `element_order` set, which causes them to use a different serialization path that ignores the `render_empty` option.

## Environment

- lutaml-model version: 0.8.0+ (main branch)
- Ruby version: 3.4.8

## Steps to Reproduce

```ruby
require 'lutaml/model'

class Subject < Lutaml::Model::Serializable
  attribute :authority, :string
  attribute :topic, :string, collection: true

  xml do
    element "subject"
    map_element "topic", to: :topic, render_empty: :as_blank
  end
end

# Fresh model - works correctly
s1 = Subject.new(authority: 'lcsh', topic: [])
puts s1.to_xml
# Output: <subject xmlns="..." authority="lcsh"><topic xmlns=""/></subject>
# ✓ Empty topic IS rendered

# Parsed model - render_empty is ignored
xml = '<subject xmlns="http://www.loc.gov/mods/v3" authority="lcsh"><topic/></subject>'
s2 = Subject.from_xml(xml)
puts s2.topic.inspect  # => []
puts s2.to_xml
# Output: <subject xmlns="..." authority="lcsh"/>
# ✗ Empty topic is NOT rendered
```

## Expected Behavior

Both fresh and parsed models should serialize empty collections as self-closing elements when `render_empty: :as_blank` is set.

## Root Cause

The `element_order` tracking mechanism, used for round-trip XML preservation, has a separate code path in `process_collection_item`:

```ruby
# lib/lutaml/xml/transformation/ordered_applier.rb, line 198-210
def process_collection_item(_root, rule, value, object, element_indices, _options)
  index = element_indices[object.name]
  value_length = value.respond_to?(:length) ? value.length : value.size

  if index < value_length  # ← Empty collection fails this check
    single_value = value[index]
    element_indices[object.name] += 1
    yield(:apply_single, rule, single_value) if block_given?
  end
  # No handling for empty collections when render_empty: :as_blank is set
end
```

When `value` is an empty array `[]`:
- `index` = 0
- `value_length` = 0
- `0 < 0` is `false`
- The rule is never applied, so empty elements are not rendered

## Suggested Fix

In `process_collection_item`, check `render_empty` option before skipping:

```ruby
def process_collection_item(_root, rule, value, object, element_indices, _options)
  index = element_indices[object.name]
  value_length = value.respond_to?(:length) ? value.length : value.size

  if index < value_length
    single_value = value[index]
    element_indices[object.name] += 1
    yield(:apply_single, rule, single_value) if block_given?
  elsif index == 0 && value_length == 0 && rule.render_empty == :as_blank
    # Render empty element when render_empty: :as_blank is set
    yield(:apply_empty, rule, nil) if block_given?
  end
end
```

Alternatively, the `element_order` path should delegate to the same skip logic used by the normal serialization path, which already respects `render_empty`.
