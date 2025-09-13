# guac-mesh-graphql

## Overview

This directory contains the **GraphQL Mesh transformation sidecar** and related tooling for the Graphtastic GUAC Spoke. It is designed for:

- **Federation-aware GraphQL transformation** (via Mesh)
- **ETL extraction** from GUAC to Dgraph (via N-Quads)
- **Self-contained, modern TypeScript project structure**
- **Containerized and local development workflows**

## Key Patterns & Rationale

### 1. Localized TypeScript Project Structure

- All TypeScript config (`tsconfig.json`), build artifacts (`dist/`), and scripts are scoped to this subproject.
- This prevents config/build pollution in the monorepo root and enables independent development, testing, and CI.
- See: [TypeScript Project References](https://www.typescriptlang.org/docs/handbook/project-references.html)

### 2. Modern TypeScript & Node.js ESM

- Uses `module: NodeNext` and `moduleResolution: NodeNext` for full ESM compatibility with Node.js 20+.
- All scripts are written in TypeScript and run via [`ts-node-esm`](https://typestrong.org/ts-node/docs/imports/).
- Mesh config can be `.ts` or `.mts` and is referenced directly in scripts.
- See: [Node.js ESM Docs](https://nodejs.org/api/esm.html), [ts-node ESM](https://typestrong.org/ts-node/docs/imports/)

### 3. Containerized Tooling Pattern

- All build, schema composition, and extraction steps are run in containers by default (using `docker compose run`).
- For local development, set `USE_LOCAL_TOOLS=1` to run tools natively.
- This ensures reproducibility, fast onboarding, and CI/CD parity.
- See: [Docker Compose Override Pattern](https://docs.docker.com/compose/extends/)

### 4. Mesh Transformation Sidecar

- The `guac-mesh-graphql` service acts as the public interface for the Spoke, wrapping the internal GUAC GraphQL API.
- Mesh applies custom transforms (see `scripts/augment-transform.ts`) to synthesize global IDs and add Apollo Federation directives.
- See: [GraphQL Mesh Docs](https://www.graphql-mesh.com/docs/getting-started), [Mesh Transforms](https://www.graphql-mesh.com/docs/handlers/graphql#transforms)

### 5. ETL Extractor

- The `scripts/extractor.ts` script (currently a diagnostic/sanity check) will be replaced with a full ETL pipeline that:
  - Introspects the Mesh GraphQL schema
  - Fetches all core node and edge types
  - Serializes results as Dgraph N-Quads RDF
  - Outputs a gzipped RDF file for bulk loading into Dgraph
- See: [Dgraph Bulk Loader](https://dgraph.io/docs/deploy/bulk-loader/), [Dgraph RDF N-Quads Format](https://dgraph.io/docs/migration/rdf-operations/)

### 6. Developer Workflow

- All operational tasks are executed through the root `Makefile` (see monorepo root).
- Use `make extract` to run the extractor (containerized by default, local override supported).
- Use `make seed` to run the full pipeline: setup, ingest, extract, and bulk load.
- See: [GNU Make Manual](https://www.gnu.org/software/make/manual/make.html)

### 7. Extending to a Full Cluster

- The Dgraph Compose file is structured to make it easy to:
  - Start only Zero (for bulk loading)
  - Start only Alpha (after loading)
  - Scale to a full cluster (multi-Zero, multi-Alpha) using Compose profiles and scaling
- See: [Dgraph Cluster with Docker Compose](https://dgraph.io/docs/deploy/docker/#running-dgraph-in-a-cluster)

## Directory Structure

```shell
guac-mesh-graphql/
├── .gitignore
├── Dockerfile
├── package.json
├── tsconfig.json
├── scripts/
│   ├── extractor.ts
│   └── extractor.wip.ts
├── build/
└── ...
```

## Benchmarking Dataset: 1million RDF

For Dgraph ETL and loader benchmarking, we use the public [1million RDF dataset](https://github.com/hypermodeinc/dgraph-benchmarks/tree/main/data):

- **RDF Data:** `guac-mesh-graphql/benchmark/1million.rdf.gz` (16MB compressed)
- **Indexed Schema:** `guac-mesh-graphql/benchmark/1million.schema` (628 bytes)
- **No-Index Schema:** `guac-mesh-graphql/benchmark/1million-noindex.schema` (471 bytes)

### Example Schema (Indexed)

```
director.film        : [uid] @reverse @count .
actor.film           : [uid] @count .
genre                : [uid] @reverse @count .
initial_release_date : datetime @index(year) .
rating               : [uid] @reverse .
country              : [uid] @reverse .
loc                  : geo @index(geo) .
name                 : string @index(hash, term, trigram, fulltext) @lang .
starring             : [uid] @count .
performance.character_note : string @lang .
tagline              : string @lang .
cut.note             : string @lang .
rated                : [uid] @reverse .
email                : string @index(exact) @upsert .
```

### Example Schema (No-Index)

```
director.film        : [uid] .
actor.film           : [uid] .
genre                : [uid] .
initial_release_date : datetime .
rating               : [uid] .
country              : [uid] .
loc                  : geo .
name                 : string @lang .
starring             : [uid] .
performance.character_note : string @lang .
tagline              : string @lang .
cut.note             : string @lang .
rated                : [uid] .
email                : string .
```

### Usage

### Makefile Targets for Benchmarking

- `make fetch-benchmark-data` — Download the RDF and both schemas to `guac-mesh-graphql/benchmark/`.
- `make clean` — Remove all downloaded benchmarking data and build artifacts.
- `make wipe-dgraph-data` — Remove all Dgraph persistent data and build output (required before each bulk load benchmark).
- `make benchmark-bulk-indexed` — Benchmark Dgraph bulk loader with the indexed schema (wipes data first, then loads and times the operation).
- `make benchmark-bulk-noindex` — Benchmark Dgraph bulk loader with the no-index schema (wipes data first, then loads and times the operation).

These targets allow you to compare Dgraph bulk load performance with and without schema indexes, using a reproducible public dataset.

## Further Reading

- [GraphQL Mesh Docs](https://www.graphql-mesh.com/docs/getting-started)
- [Dgraph Bulk Loader](https://dgraph.io/docs/deploy/bulk-loader/)
- [Dgraph RDF N-Quads Format](https://dgraph.io/docs/migration/rdf-operations/)
- [Node.js ESM Modules](https://nodejs.org/api/esm.html)
- [ts-node ESM Support](https://typestrong.org/ts-node/docs/imports/)
- [Docker Compose Profiles](https://docs.docker.com/compose/profiles/)
- [Dgraph Cluster with Docker Compose](https://dgraph.io/docs/deploy/docker/#running-dgraph-in-a-cluster)
- [GNU Make Manual](https://www.gnu.org/software/make/manual/make.html)
