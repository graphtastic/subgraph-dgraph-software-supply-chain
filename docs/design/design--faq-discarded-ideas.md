### **Design FAQ: Architectural Alternatives & Discarded Paths**

This document serves as an appendix to the primary design for the `subgraph-dgraph-software-supply-chain` Spoke. Its purpose is to record the architectural due diligence performed during the design phase. By documenting the alternatives considered and the explicit rationale for their rejection, we provide clarity on the chosen path and create a valuable resource that preserves the context of our architectural decisions.

#### **1. Q: Why not just use the GraphQL API with batched mutations for all data loading instead of a file-based bulk loader?**

**A:** This was the primary architectural trade-off considered for data ingestion. While using batched GraphQL mutations is the standard pattern for real-time and incremental updates, it is fundamentally ill-suited for the initial, large-scale data seeding required by this project. The RDF N-Quad + Dgraph Loader approach was chosen specifically to handle the massive performance requirements of the initial load.

The optimal production architecture is a hybrid approach: use the bulk loader for the initial seed, and reserve batched mutations for potential future near-real-time synchronization needs.

**Comparative Analysis: Ingestion Strategy**

| Feature Axis | Strategy A: Batched GraphQL Mutations | Strategy B: RDF N-Quads + Dgraph Loaders |
| :--- | :--- | :--- |
| **Performance (Initial Load)** | **Poor to Moderate.** Limited by network latency and transactional overhead. Would be orders of magnitude too slow for terabyte-scale seeding. | **Excellent.** `dgraph bulk` is an offline tool optimized for maximum ingestion speed, bypassing the live API. |
| **Implementation Complexity** | **Higher.** Requires custom logic for buffering, batching, API error handling, and retries. | **Lower.** The extractor's logic is simple (stream text to a file). Complexity is handled by Dgraph's mature, purpose-built CLI tools. |
| **Transactional Guarantees** | **Strong & Granular.** Each batch is a single, atomic transaction. | **Different Model.** `dgraph bulk` is an all-or-nothing offline operation. |
| **Coupling / Portability** | **Low.** The extractor only depends on the standard GraphQL endpoint. | **High.** The output format and loading mechanism are tightly coupled to Dgraph's specific tooling. |

---

#### **2. Q: Why use RDF N-Quads as the intermediate format instead of a more GraphQL-native JSON format?**

**A:** The choice of an intermediate format required balancing fidelity to the GraphQL object model, portability, and the practical requirements of Dgraph's high-performance loaders. RDF N-Quads were selected as the optimal pragmatic choice. They are a true graph format, are a portable industry standard, and are natively supported by Dgraph's loaders. While formats like JSON-LD are conceptually closer to the GraphQL ecosystem, they would require an extra, costly transformation step before they could be loaded into Dgraph, negating their benefits.

**Comparative Analysis: Intermediate Data Format**

| Format | Fidelity to GraphQL API Model | Portability / Interoperability | Performance for Dgraph Loading |
| :--- | :--- | :--- | :--- |
| **RDF N-Quads** | Good. Maps well to a graph, but is a triple model, not an object model. | High. A W3C standard for graph data interchange. | **Excellent.** Natively supported and highly optimized in Dgraph loaders. |
| **JSON-LD** | Very Good. It's JSON, which is native to the ecosystem, but with full graph semantics. | **Excellent.** A W3C web standard. | Moderate. Requires a pre-processing step to convert to N-Quads or Dgraph JSON. |
| **Dgraph JSON** | Very Good. Maps almost 1:1 to GraphQL objects. | **None.** Completely proprietary to Dgraph. | **Excellent.** Native format for Dgraph. |
| **GraphQL JSON Result**| Perfect. It *is* the API model. | Poor. Not a graph format; requires complex re-hydration logic. | Poor. Would require a custom loader to parse and convert into mutations. |

---

#### **3. Q: Could we use a hybrid `JSON-LD -> Dgraph JSON` pipeline to stay in the JSON ecosystem longer?**

**A:** This hybrid approach was considered as a way to leverage JSON-native tooling. However, the analysis concluded that this pipeline would introduce significant, unnecessary complexity. The central step, transforming from the JSON-LD graph format to the Dgraph JSON graph format, cannot be accomplished with simple tools like `jq`. It requires writing a new, custom, and stateful transformation application responsible for mapping entity identifiers and restructuring the graph. This custom tool would be complex to build and maintain, directly contradicting the goal of avoiding "bespoke hilarity." The original RDF pipeline is simpler, more performant, and leverages mature, existing tools more effectively.

---

#### **4. Q: Why not use a high-performance binary format like Jelly for the intermediate data artifact?**

**A:** A binary format like Jelly was explored for its potential performance and compression benefits. The idea was discarded for several critical, practical reasons. Most importantly, Dgraph's loaders do not support Jelly, which would necessitate an extra conversion step from Jelly back to N-Quads, eliminating any performance gain. Furthermore, the opacity of a binary format severely hinders debuggability compared to a simple, human-readable text format like N-Quads.

**Comparative Analysis: Intermediate Artifact Format**

| Evaluation Criteria | Gzipped N-Quads (Chosen Path) | Jelly (Discarded Path) | Winner |
| :--- | :--- | :--- | :--- |
| **End-to-End Performance** | **High.** `GraphQL -> N-Quad Text -> Dgraph`. One simple transformation step. | **Lower.** `GraphQL -> Jelly Binary -> N-Quad Text -> Dgraph`. Requires two full transformation steps. | **N-Quads** |
| **Implementation Complexity** | **Low.** The extractor script performs simple, stateless string formatting. | **High.** Requires a specialized library and a new Jelly-to-N-Quad converter tool. | **N-Quads** |
| **Developer Experience (Debuggability)** | **Excellent.** Can be inspected with standard shell tools (`zcat`, `head`, `grep`). | **Poor.** Opaque binary blob. Requires a specialized dumper tool for inspection. | **N-Quads** |
| **Portability / Interoperability**| **Excellent.** N-Quads are a W3C standard supported by the entire RDF ecosystem. | **Low.** Jelly is a niche format not directly usable by most other graph systems. | **N-Quads** |
