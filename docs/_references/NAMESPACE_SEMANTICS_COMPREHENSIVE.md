# Namespace Semantics: Comprehensive Design

## Overview

Namespace assignment in Lutaml::Model follows a **three-source priority system**:

1. **Mapping Level** (HIGHEST) - Explicit override on `map_element`/`map_attribute`
2. **Type Level** (MEDIUM) - Namespace declared by Type class via `xml_namespace`
3. **Context Level** (LOWEST) - Inherited from parent/hosting element based on `form` rules

This design ensures MECE (Mutually Exclusive, Collectively Exhaustive) handling of all namespace scenarios.

## Three Sources of Namespace

### Source 1: Mapping Level (Explicit Override)

**Priority**: HIGHEST - Overrides type namespace and context inheritance

**Mechanisms**:
```ruby
xml do
  map_element "name", to: :name, namespace: <value>
  map_attribute "id", to: :id, namespace: <value>
end
```

Where `<value>` can be:
- XmlNamespace class
- String URI
- `:blank` symbol (proposed)
- `:inherit` symbol (existing)
- `nil` (proposed: should mean "not set")

### Source 2: Type Level (Type Namespace)

**Priority**: MEDIUM - Applies when no mapping override

**Mechanism**:
```ruby
class MyType < Lutaml::Model::Type::String
  xml_namespace MyNamespace
end

class Model < Lutaml::Model::Serializable
  attribute :data, MyType  # Inherits MyNamespace from type
end
```

**Behavior**: Type's namespace applies unless mapping explicitly overrides

### Source 3: Context Level (Form-Based Inheritance)

**Priority**: LOWEST - Applies when no mapping override and no type namespace

**For Elements**:
- Controlled by `elementFormDefault` (:qualified or :unqualified)
- `:qualified` → inherit parent namespace
- `:unqualified` → blank namespace (no inheritance)

**For Attributes**:
- Controlled by `attributeFormDefault` (:qualified or :unqualified)
- `:qualified` → use hosting element's namespace
- `:unqualified` → blank namespace (W3C: attributes never inherit default namespace)

## Proposed Namespace Values (MECE)

### At Mapping Level

| Value | Meaning | Priority | Use Case |
|-------|---------|----------|----------|
| `XmlNamespace class` | Explicit namespace | OVERRIDE | Standard case |
| `"http://..."` string | Inline URI | OVERRIDE | One-off namespace |
| `:blank` symbol | Blank namespace | OVERRIDE | Explicitly no namespace |
| `:inherit` symbol | Inherit parent's namespace | OVERRIDE | Explicit inheritance |
| `nil` | Not set, use default | FALLBACK | Let type/context decide |
| Omitted | Not set, use default | FALLBACK | Same as nil |

### At Type Level

```ruby
class MyType < Lutaml::Model::Type::Value
  xml_namespace SomeNamespace  # Only XmlNamespace class allowed
end
```

**No symbols allowed** - Type namespace is always explicit or omitted

### At Model Level (xml block)

```ruby
xml do
  element "name"
  namespace <value>  # Applies to this model's element
end
```

**Allowed values**: Same as mapping level

## Semantic Distinctions

### `namespace :blank` vs `namespace nil` vs Omitting

| Declaration | Set? | Namespace | Overrides Type? | Overrides Form? |
|-------------|------|-----------|-----------------|-----------------|
| `namespace :blank` | ✅ Yes | Blank | ✅ Yes | ✅ Yes |
| `namespace nil` | ❌ No | (depends) | ❌ No | ❌ No |
| Omit `namespace` | ❌ No | (depends) | ❌ No | ❌ No |

**Key Insight**: `:blank` is the explicit override, `nil` and omitting are equivalent (not set)

### Resolution Priority (Mutually Exclusive)

**For Elements**:
```
1. namespace: XmlNamespace/String → use that namespace
2. namespace: :blank → blank namespace (no xmlns or xmlns="")
3. namespace: :inherit → parent's namespace
4. namespace: nil/omitted → continue to next step ↓
5. Type has xml_namespace → Type's namespace
6. form: :qualified OR elementFormDefault: :qualified → parent's namespace
7. form: :unqualified OR elementFormDefault: :unqualified → blank namespace
8. Default → blank namespace
```

**For Attributes**:
```
1. namespace: XmlNamespace/String → use that namespace
2. namespace: :blank → blank namespace (no prefix)
3. namespace: nil/omitted → continue to next step ↓
4. Type has xml_namespace → Type's namespace
5. form: :qualified OR attributeFormDefault: :qualified → hosting element's namespace
6. form: :unqualified OR attributeFormDefault: :unqualified → blank namespace
7. Default → blank namespace (W3C: attributes never inherit default namespace)
```

## Implementation Requirements

### Phase 1: Support `:blank` Symbol

**File**: [`lib/lutaml/model/xml/mapping.rb`](lib/lutaml/model/xml/mapping.rb)

**Change**:
```ruby
def namespace(uri_or_class, prefix = nil)
  # Handle :blank symbol
  if uri_or_class == :blank
    @namespace_class = nil
    @namespace_uri = nil
    @namespace_set = true  # CRITICAL: Mark as explicitly set
    @namespace_param = :blank  # Store original symbol
    return
  end
  
  # Handle :inherit symbol (already supported)
  if uri_or_class == :inherit
    @namespace_param = :inherit
    @namespace_set = true
    return
  end
  
  # nil means "not set" - don't set @namespace_set = true
  if uri_or_class.nil?
    # Leave @namespace_set as false
    return
  end
  
  # Rest of existing logic for classes and strings...
end
```

### Phase 2: Handle `:blank` in Resolution

**File**: [`lib/lutaml/model/xml/mapping_rule.rb`](lib/lutaml/model/xml/mapping_rule.rb)

**Change in `normalize_namespace`**:
```ruby
def normalize_namespace(namespace, prefix)
  return nil if namespace.nil?  # Not set
  return :blank if namespace == :blank  # Explicit blank (store symbol)
  return nil if namespace == :inherit  # Handled in resolution
  
  # ... rest of existing logic
end
```

**Change in `resolve_element_namespace`** (line ~366):
```ruby
# 0. FIRST: Check for explicit namespace: :blank
if @namespace_param == :blank
  return { uri: nil, prefix: nil, ns_class: nil, explicit_blank: true }
end

# 1. Check for explicit namespace: nil (deprecated, same as omitting)
if namespace_set? && @namespace.nil? && @namespace_param.nil?
  return { uri: nil, prefix: nil, ns_class: nil }
end

# ... rest of existing logic
```

### Phase 3: Generate `xmlns=""` When Needed

**Files**: All three adapters

**Logic**: Add `xmlns=""` when:
```ruby
if ns_info[:explicit_blank] && parent_uses_default_namespace?
  attributes["xmlns"] = ""
end
```

**Condition**: Only when `:blank` is explicit AND parent has default namespace

## Usage Examples

### Example 1: Remove Namespace in Inheritance

```ruby
class Parent < Lutaml::Model::Serializable
  attribute :data, :string
  
  xml do
    element "parent"
    namespace ParentNamespace  # http://example.com/parent
    map_element "data", to: :data
  end
end

class Child < Parent
  xml do
    element "child"
    namespace :blank  # Remove parent's namespace
  end
end

child = Child.new(data: "test")
puts child.to_xml
# <child><data>test</data></child>
```

### Example 2: Override Type Namespace

```ruby
class MyType < Lutaml::Model::Type::String
  xml_namespace TypeNamespace  # Type has namespace
end

class Model < Lutaml::Model::Serializable
  attribute :typed_data, MyType
  attribute :blank_data, MyType
  
  xml do
    element "model"
    # typed_data uses Type's namespace
    map_element "typed", to: :typed_data
    # blank_data overrides to blank namespace
    map_element "blank", to: :blank_data, namespace: :blank
  end
end

model = Model.new(typed_data: "a", blank_data: "b")
puts model.to_xml
# <model>
#   <type:typed xmlns:type="...">a</type:typed>
#   <blank>b</blank>
# </model>
```

### Example 3: Form Override vs Blank Override

```ruby
class Model < Lutaml::Model::Serializable
  attribute :qualified, :string
  attribute :unqualified_form, :string
  attribute :explicit_blank, :string
  
  xml do
    element "model"
    namespace ModelNamespace
    
    # Inherits qualified from elementFormDefault
    map_element "qualified", to: :qualified
    
    # Form override (still can inherit in some contexts)
    map_element "unqualified", to: :unqualified_form, form: :unqualified
    
    # Explicit blank (NEVER has namespace, even if type has one)
    map_element "blank", to: :explicit_blank, namespace: :blank
  end
end
```

**Distinction**:
- `form: :unqualified` → blank namespace per schema rules (can be overridden by type namespace)
- `namespace: :blank` → blank namespace ALWAYS (highest priority override)

## Complete Namespace Value Semantics

### MECE Table

| Mapping Value | namespace_set? | namespace_param | Behavior |
|---------------|----------------|-----------------|----------|
| `SomeNamespace` class | ✅ true | Class | Use that namespace |
| `"http://..."` string | ✅ true | String | Use inline URI |
| `:blank` symbol | ✅ true | :blank | Blank namespace (override all) |
| `:inherit` symbol | ✅ true | :inherit | Parent's namespace (override all) |
| `nil` | ❌ false | nil | Not set, use type/context |
| Omitted | ❌ false | nil | Not set, use type/context |

## Migration from Current System

### What Changes

**Breaking**: None for existing valid code

**New Features**:
- `:blank` symbol now supported
- `:inherit` continues to work
- Explicit blank namespace possible

**Clarifications**:
- `nil` is now clearly "not set" (same as omitting)
- Previously `namespace nil` on map_element threw error (now: use `:blank` instead)

### Migration Guide

**Old Pattern** (error):
```ruby
map_element "name", to: :name, namespace: nil  # ERROR
```

**New Pattern**:
```ruby
map_element "name", to: :name, namespace: :blank  # Explicit blank
# OR
map_element "name", to: :name  # Omit (context-dependent)
```

## Testing Requirements

### Test Matrix

| Scenario | mapping ns | type ns | form | Expected Result |
|----------|-----------|---------|------|-----------------|
| 1 | MyNs | - | - | MyNs |
| 2 | :blank | TypeNs | - | Blank (overrides type) |
| 3 | :blank | - | :qualified | Blank (overrides form) |
| 4 | :inherit | - | :unqualified | Parent ns (overrides form) |
| 5 | nil | TypeNs | - | TypeNs |
| 6 | nil | - | :qualified | Parent ns |
| 7 | nil | - | :unqualified | Blank |
| 8 | omit | TypeNs | - | TypeNs |
| 9 | omit | - | :qualified | Parent ns |
| 10 | omit | - | :unqualified | Blank |

### New Test Files

1. ✅ `namespace_inheritance_override_spec.rb` - Class inheritance
2. ✅ `namespace_w3c_compliance_spec.rb` - W3C compliance
3. TODO: Update both to use `:blank` instead of `nil`

## Implementation Checklist

- [ ] Update `Mapping.namespace` to accept `:blank` symbol
- [ ] Store `:blank` in `@namespace_param` 
- [ ] Set `@namespace_set = true` for `:blank`
- [ ] Handle `:blank` in `normalize_namespace`
- [ ] Handle `:blank` in `resolve_element_namespace` (return `explicit_blank: true`)
- [ ] Handle `:blank` in `resolve_attribute_namespace` (return `explicit_blank: true`)
- [ ] Generate `xmlns=""` in adapters when `explicit_blank` and parent has default ns
- [ ] Update test suites to use `:blank`
- [ ] Document in user guide
- [ ] Add examples to README

## Documentation Requirements

### User Guide

**File**: [`docs/_guides/xml-namespaces.adoc`](docs/_guides/xml-namespaces.adoc)

**New Section**: "Explicit Blank Namespace"

**Content**:
- When to use `:blank`
- Difference from omitting namespace
- Examples with inheritance
- xmlns="" generation behavior

### API Reference

**Content**:
- `namespace` method parameter options
- Semantic meaning of each option
- Priority order
- Examples

## Success Criteria

- [ ] `:blank` symbol accepted in `namespace` method
- [ ] `xmlns=""` generated when parent has default namespace
- [ ] Inheritance override tests pass (8/8)
- [ ] W3C compliance tests updated and passing
- [ ] No regressions in existing 87 passing tests
- [ ] Clear documentation of semantics

---

**Status**: DESIGN COMPLETE
**Next**: Implement `:blank` symbol support
**Estimated Effort**: 3-4 hours