### Understanding XML Namespace Declaration Planning in LutaML

If you're new to XML and concepts like "namespace declaration planning," don't worry—this guide breaks it down step by step. I'll explain it in simple terms, like teaching a beginner, without assuming you know technical jargon. We'll start with the basics, then build up to how "declaration planning" fits in. This is based on how the LutaML library (a tool for working with XML data in Ruby) handles XML namespaces during serialization (turning data into XML format).

#### Step 1: What Are XML Namespaces and Declarations? (The Basics)
- **XML Basics**: XML is a way to structure data, like a tree of elements (e.g., `<book><title>Harry Potter</title></book>`). Elements can have names, attributes, and nested children.
- **Namespaces**: Imagine two companies using the same element name, like `<address>`, but meaning different things (one for mailing, one for web URLs). Namespaces solve this by adding a "prefix" or "scope" to avoid confusion. A namespace is like a unique ID (a URI, e.g., "http://example.com/books") that groups related elements.
  - **Declaration**: To use a namespace in XML, you "declare" it with an attribute like `xmlns="http://example.com/books"` (default namespace) or `xmlns:bk="http://example.com/books"` (prefixed namespace).
  - Example without namespace: `<book><title>Harry Potter</title></book>`
  - With default namespace: `<book xmlns="http://books.com"><title>Harry Potter</title></book>` (all elements inside belong to "http://books.com").
  - With prefixed: `<bk:book xmlns:bk="http://books.com"><bk:title>Harry Potter</bk:title></bk:book>`.
- **Why Plan Declarations?** In complex XML (with nested elements from multiple namespaces), deciding *where* to declare namespaces matters. Declare too high (e.g., all at the root), and it might cause clutter or conflicts. Declare too low, and you repeat declarations unnecessarily. "Declaration Planning" is the process of deciding optimally where and how to place these `xmlns` attributes.

LutaML uses a smart system to handle this automatically, following rules from the W3C (the standards body for XML). It aims for "minimal-subtree" (declare namespaces only where needed, as low in the tree as possible) while allowing some hoisting (moving declarations higher up) for simplicity.

#### Step 2: The Big Picture – LutaML's Three-Phase Architecture
LutaML breaks namespace handling into three phases to make XML output correct and efficient:
1. **Discovery Phase**: Scan the entire data tree to find all namespaces used and where they appear. (Like making a map of your house to see where lights are needed.)
2. **Planning Phase**: Use the discovery info to decide *where* to declare each namespace and what prefixes to use. This is where "Declaration Planning" happens—it's the brain that creates a blueprint.
3. **Serialization Phase**: Actually build the XML using the plan (no thinking here, just follow the blueprint).

The goal: Produce clean XML that's W3C-compliant, avoids duplicates, and respects user settings (e.g., force certain declarations at the root).

#### Step 3: What is "XML Declaration Planning"? (The Core Concept)
Declaration Planning is Phase 2. It's like an architect drawing up plans for where to install electrical outlets in a building. Based on the "map" from Phase 1, it decides:
- **Hoisting**: Where to "hoist" (place) each namespace declaration. Hoisting means declaring a namespace at an element so it's available to all its children.
  - Prefer low in the tree (minimal scope, clearer ownership).
  - But sometimes hoist higher (e.g., to the root) if configured or to avoid repetition.
- **Prefix vs. Default**: For each namespace:
  - Default (`xmlns="uri"`): Cleaner for the main namespace; no prefixes on element names.
  - Prefixed (`xmlns:pre="uri"`): Needed for multiple namespaces or attributes (attributes can't use default; they must be prefixed).
  - Blank (`xmlns=""`): Resets to no namespace for subtrees.
- **Prefix Assignment**: Choose prefixes (e.g., "bk" for books) without conflicts. If a user wants a specific prefix, use it; otherwise, generate safe ones (e.g., avoid reusing the same prefix for different URIs).
- **Key Rules (Principles)**:
  - **Never Declare Twice**: Once a namespace is declared (hoisted), children inherit it—don't repeat.
  - **Eligibility**: Only certain elements can hoist:
    - If an element belongs to a namespace, it can hoist it (as default or prefixed).
    - Other elements can hoist prefixed namespaces if allowed by settings (`namespace_scope`).
  - **Prioritize Prefixes for Attributes**: If any attribute needs a namespace, hoist it prefixed (not default).
  - **Forced Declarations**: If set to "always," declare even if unused (for strict formats like Office XML).
  - **No Conflicts**: Same URI can't have multiple prefixes; prefixes must be unique document-wide.

The output of this phase is a "Declaration Plan"—a tree structure mirroring your data, with instructions like:
- At this element, declare these `xmlns` attributes.
- Use this prefix for the element/attribute name.

#### Step 4: How Does Declaration Planning Work? (Step-by-Step Algorithm)
Using info from Discovery (e.g., namespace counts, needs for prefix/default):
1. **Traverse the Tree Top-Down**: Start from the root, visit each node (element).
2. **Check Needs**: For each namespace URI, see if descendants need it (from counts).
3. **Decide Hoisting**:
   - If the current node is eligible (belongs to the URI or has scope permission) and it's the best spot (closest to needs), hoist it here.
   - Otherwise, pass to children—let them hoist lower.
   - Root is always eligible as a backup.
4. **Handle Forced Hoists**: Add declarations for "always" modes, but remove if an ancestor already hoisted.
5. **Assign Prefixes**: Globally resolve prefixes:
   - Prefer defaults from config (e.g., "ex" for "http://example.com").
   - Generate unique ones if conflicts (e.g., "ns1", "ns2").
   - If prefix needed (e.g., for attributes or user request), force prefixed over default.
6. **Build the Plan**: Create a structure with hoist instructions and usage prefixes for each element/attribute.

#### Step 5: Simple Examples
- **Example 1: Basic Single Namespace (No Planning Needed)**
  - Data: A book model in "http://books.com".
  - Plan: Hoist at root as default (`xmlns="http://books.com"`).
  - XML: `<book xmlns="http://books.com"><title>Harry Potter</title></book>`

- **Example 2: Multi-Namespace with Local Declarations (Default Behavior)**
  - Data: Root in "http://a.com", child in "http://b.com".
  - Plan: Hoist "http://a.com" at root (default). Hoist "http://b.com" at child (default, since not eligible for root hoist).
  - XML: `<root xmlns="http://a.com"><child xmlns="http://b.com">...</child></root>`

- **Example 3: Hoisted to Root with Prefix (Using `namespace_scope`)**
  - Data: Same as above, but root allows scope for "http://b.com".
  - Plan: Hoist both at root; "http://a.com" default, "http://b.com" prefixed ("b").
  - XML: `<root xmlns="http://a.com" xmlns:b="http://b.com"><b:child>...</b:child></root>`
  - Why? Cleaner, all declarations in one place.

- **Example 4: Attribute Forcing Prefix**
  - Data: Element with attribute in same namespace.
  - Plan: Hoist as prefixed (not default), since attributes need prefixes.
  - XML: `<bk:book xmlns:bk="http://books.com" bk:id="1"><bk:title>Harry Potter</bk:title></bk:book>`

#### Step 6: Why This Matters and Tips for Beginners
- **Benefits**: Makes XML smaller, clearer, and less error-prone. Follows W3C "minimal-subtree" for modularity (e.g., copy a subtree without losing context).
- **Common Pitfalls**:
  - Unused namespaces: With "auto" mode, they're skipped; use "always" if required.
  - Prefix Inheritance: Children reuse parent's declarations automatically.
  - Attributes: Always prefixed if namespaced—no defaults allowed.
- **In LutaML Code**: You define models with `xml do ... end` blocks, adding `namespace_scope` to control hoisting. The planning happens automatically when you call `to_xml`.

If this still feels confusing, think of it like organizing a party: Discovery finds who needs what (drinks, food); Planning decides where to place supplies (kitchen or tables); Serialization serves it. For more details, check LutaML docs on namespaces.

### Understanding how Declaration Planning Integrates with XmlDataModel and Adapters

1. The `XmlDataModel` serves as the core content tree (a hierarchical representation of the XML structure, including elements, attributes, and text) that is serialized by adapters. It is namespace-aware via the `namespace_class` on `XmlElement` and `XmlAttribute`, but it does not contain prefix or hoisting decisions—these are decoupled into the `DeclarationPlan` for flexibility (e.g., allowing different prefix strategies without modifying the data tree).

   To fit attribute prefix decisions:
   - The `DeclarationPlan` mirrors the `XmlDataModel` tree structure exactly (isomorphic), with `ElementNode` corresponding to each `XmlElement`, and `AttributeNode` corresponding to each `XmlAttribute`.
   - For attributes, the `DeclarationPlan::AttributeNode#use_prefix` (and optionally `#namespace_uri`) stores the resolved prefix decision (e.g., "bk" for "bk:id"). This is populated during planning based on the attribute's `namespace_class` (from `XmlAttribute`), W3C rules (attributes must be prefixed if namespaced), and global prefix assignments (to avoid conflicts).
   - During plan construction (in `DeclarationPlanner`), traverse the `XmlDataModel` tree to build the parallel `DeclarationPlan` tree:
     - For each `XmlElement#attributes` array, create a matching `ElementNode#attribute_nodes` array of `AttributeNode`s.
     - Assign `use_prefix` per attribute based on its `namespace_class`: If namespaced, require a prefix (never default); if blank, `nil`.
     - This keeps prefix decisions separate from the data, allowing re-planning (e.g., for different outputs) without altering `XmlDataModel`.

   This integration ensures the plan "annotates" the data tree without embedding logic in it, aligning with the "dumb adapters" goal—adapters just apply the plan to the data.

2. Adapters (e.g., Nokogiri, Oga, Ox) should traverse the `XmlDataModel` and `DeclarationPlan` trees in parallel (recursively, top-down from root), matching nodes by structure/position rather than lookup. This avoids runtime searches and ensures efficiency:

   - **For Elements**: Start with `XmlElement` (data) and corresponding `DeclarationPlan::ElementNode` (plan).
     - Create the XML element using `XmlElement#qualified_name(plan.use_prefix)` (applies prefix if set).
     - Add `xmlns` attributes from `plan.hoisted_declarations` (the hash of prefix => URI).
     - Recurse to children: For each `XmlElement#children` (if `XmlElement`), match to `plan.element_nodes` by index/order (assuming the plan was built in the same traversal order as the data tree).

   - **For Attributes**: When processing an element's attributes, iterate `XmlElement#attributes` and match to `DeclarationPlan::ElementNode#attribute_nodes` by index (1:1 correspondence, since attributes are ordered in the data model).
     - Create each XML attribute using `XmlAttribute#qualified_name(plan_attribute.use_prefix)` (applies prefix).
     - No need for name or `namespace_class` lookup—position ensures the correct decision (e.g., first attribute in data matches first `AttributeNode` in plan).
     - If robustness is needed (e.g., for future changes), optionally validate match by comparing `XmlAttribute#name` + `namespace_class` to inferred values in `AttributeNode#namespace_uri`, but index is sufficient and faster.

   This parallel traversal keeps adapters simple: No decisions, just apply prefixes/declarations at each matched node. If the trees mismatch (e.g., due to build error), raise an exception.