# Subgraph: Dgraph Software Supply Chain

> ## 🚧 **Architectural Blueprints Ahead! 🚀**
>
> Welcome! This repository contains a **work-in-progress** implementation. While the code is still evolving, the architectural and design documentation here represents our north star for building a high-performance, federated graph for software supply chain security. We're excited to have you here and welcome you to explore the designs and join us in the discussions on CNCF Slack in [#initiative-supply-chain-security-insights](https://cloud-native.slack.com/archives/C09A8VBEUNM).

## 1. Overview

This repository contains the source code, operational configuration, and detailed architectural documentation for the `subgraph-dgraph-software-supply-chain`. This service is a foundational ["Spoke"](https://github.com/graphtastic/platform/blob/main/docs/design/tome--graphtastic-platform-docker-compose.md#31-the-hub-and-spoke-model) within the [Graphtastic Platform](https://github.com/graphtastic/platform/blob/main/README.md#the-graphtastic-platform), designed to provide a high-performance, federated GraphQL API for software supply chain security data.

### 1.1. Strategic Goals

This subgraph serves two primary, strategic purposes:

1. **CNCF Demonstrator:** To act as a reference implementation and standalone demonstrator for the [CNCF Software Supply Chain Insights initiative](https://github.com/cncf/toc/issues/1709).
2. **Federated Spoke:** To function as a fully compliant, federated Spoke within the Graphtastic supergraph, aggregating and exposing security data from multiple sources.

### 1.2. Core Technology

Our architecture is built on a foundation of powerful, cloud-native technologies:

* **Data Source:** [GUAC (Graph for Understanding Artifact Composition)](https://guac.sh/) instances, which generate rich software supply chain metadata.
* **Persistence Layer:** [Dgraph](https://dgraph.io/), a distributed, native GraphQL graph database chosen for its horizontal scalability and high-performance query capabilities.
* **API Layer:** A GraphQL API designed from the großund up to be compliant with the [Apollo Federation](https://www.apollographql.com/docs/federation/) specification.
* **Development Environment:** A modular, multi-stack [Docker Compose](https://docs.docker.com/compose/) environment, orchestrated with `make` for a seamless and reproducible developer experience.

## 2. Architecture

This subgraph follows a decoupled, schema-driven ETL (Extract, Transform, Load) architecture to ingest data. The entire ingestion pipeline is an internal implementation detail, encapsulated within the Spoke's boundary. This "Spoke as a Black Box" approach is a core principle of the Graphtastic Platform, ensuring that the Spoke's public contract is its GraphQL API and nothing more.

```mermaid
graph LR

    %% -- DIAGRAM DEFINITION --

    %% An external component, the entry point for all queries.
    SupergraphGateway(Supergraph Gateway)

    subgraph "Spoke Boundary [subgraph-dgraph-software-supply-chain]"
        direction LR

        %% The public-facing contract of this Spoke.
        SpokeEndpoint("fa:fa-plug Public GraphQL Endpoint<br/>:8080/graphql")

        subgraph "Internal ETL & Persistence"
            direction LR
            
            %% The internal data processing pipeline.
            GUAC[GUAC API Source] --> Mesh[GraphQL Mesh]
            Mesh --> Extractor[Extractor Tool]
            Extractor --> RDF([RDF Artifact])
            RDF --> Loader[Dgraph Loader]
            Loader --> Dgraph[(fa:fa-database Dgraph Cluster)]
        end

        %% Data flows from the internal Dgraph to the public endpoint.
        Dgraph -- "Serves data from" --> SpokeEndpoint
        
        %% CLIPPING FIX: This invisible node acts as a spacer, forcing the layout
        %% engine to allocate more horizontal space and preventing clipping.
        SpokeEndpoint --- InvisibleSpacer
    end

    %% -- ADDITIONAL CONTEXTUAL SUBGRAPHS --
    subgraph "Other Spokes (subgraphs)"
        direction TB
        GitHubArchive("fa:fa-github GitHub Archive")
        Blogs("fa:fa-rss Blogs")
    end

    %% Define the relationships to the new contextual sources.
    SupergraphGateway -- "Federates" --> GitHubArchive
    SupergraphGateway -- "Federates" --> Blogs
    
    %% Queries flow from the Gateway to our Spoke's endpoint.
    SupergraphGateway -- "Federated GraphQL Query" --> SpokeEndpoint

    %% -- ANNOTATION --
    %% A non-directional link positioned below the main flow clearly marks this as an annotation.
    Mesh -.- MeshNote(
        fa:fa-cogs Transforms Upstream API: <br/>
        - Fixes global identity <br/>
        - Replaces Node-Union anti-pattern <br/>
        - Adds federation directives
    )

    %% -- STYLING & THEME SUPPORT --
    %% classDef is used to create theme-aware styles for visual hierarchy.
    classDef external fill:#f8f9fa,stroke:#6c757d,stroke-width:2px,stroke-dasharray: 5 5,color:#495057
    classDef endpoint fill:#e7f5ff,stroke:#1c7ed6,stroke-width:3px,color:#1864ab
    classDef annotation fill:#fff9db,stroke:#fcc419,stroke-width:2px,color:#c28c0c
    classDef invisible stroke:none,fill:none

    %% Applying the classes to the nodes.
    class SupergraphGateway,GitHubArchive,Blogs external
    class SpokeEndpoint endpoint
    class MeshNote annotation
    class InvisibleSpacer invisible
```

### 2.1. Data Ingestion Flow

1. **Extract & Transform:** A high-fidelity extractor tool queries one or more source GUAC GraphQL APIs. It uses GUAC's own pre-defined query files to ensure robustness. The extracted data is transformed into compressed RDF N-Quad files, a format optimized for Dgraph's loaders.
2. **Load:** The generated RDF files are loaded into Dgraph using its high-performance native tooling (`dgraph bulk` for initial population and `dgraph live` for incremental updates).
3. **Deduplication:** The Dgraph schema is programmatically augmented with `@id` directives on natural business keys. This pushes the responsibility for data deduplication down into the database layer, enabling idempotent upserts and ensuring that data from multiple GUAC sources is correctly merged into a single, canonical entity.

For a complete breakdown of this architecture, please see the core implementation design:

* [**`docs/design/design--guac-to-dgraph.md`**](./docs/design/design--guac-to-dgraph.md)

## 3. Local Development



### 3.0. Storage Mode: Bind Mounts Only (for now)

Currently, GUAC Postgres data is stored in a local bind-mounted directory (`./dgraph-stack/guac-data`).

**TODO:** Add support for Docker named volumes for GUAC Postgres data.

- Data is always stored in `./dgraph-stack/guac-data` on your host.
- No Docker volume support for GUAC Postgres yet.

---

### 3.1. Network Architecture: Internal vs. External Access

This project uses two Docker networks for security and modularity:

* **Internal network (`dgraph-net`)**: Used for private communication between Dgraph services (Zero, Alpha, Ratel). Not accessible from outside Docker.
* **External network (`graphtastic_net`)**: Used to expose selected service endpoints to the host and to other stacks in the Graphtastic platform.


**Service network membership:**

| Service         | Internal (`dgraph-net`) | External (`graphtastic_net`) | Host Accessible? | Purpose |
|-----------------|:----------------------:|:----------------------------:|:----------------:|:--------|
| dgraph-zero     |           ✔            |              ✗               |        No        | Cluster coordination only |
| dgraph-alpha    |           ✔            |              ✔               |   Yes (API)      | GraphQL/DQL API, data plane |
| dgraph-ratel    |           ✔            |              ✔               |   Yes (UI)       | Web UI for admin/dev |

> **How is Ratel accessible from the host?**
>
> Ratel is accessible from your host because its service is attached to both the internal `dgraph-net` (for private communication with Dgraph Alpha) **and** the external `graphtastic_net` (which exposes its port to the host and other stacks). The Compose file maps port `8000` to your host, so you can open [http://localhost:8000](http://localhost:8000) in your browser.

<details>
<summary><strong>How to debug the internal Docker network from the host</strong></summary>

Sometimes you need to inspect or debug services that are only on the internal Docker network (`dgraph-net`). Here are some useful techniques:

**1. Run a temporary debug container on the internal network:**

```bash
docker run -it --rm --network dgraph-net busybox sh
# or for more tools:
docker run -it --rm --network dgraph-net nicolaka/netshoot
```

You can now use tools like `ping`, `nslookup`, or `curl` to reach other containers by their service name (e.g., `dgraph-zero:5080`, `dgraph-alpha:8080`).

**2. Inspect the network and connected containers:**

```bash
docker network inspect dgraph-net
```

This will show which containers are attached and their internal IP addresses.

**3. Exec into a running service container:**

```bash
docker exec -it <container_name> sh
# Example:
docker exec -it dgraph-alpha sh
```

**4. Port-forward a service for temporary host access:**

If you need to access a service that's only on the internal network, you can use `docker port` or set up a temporary port-forward:

```bash
# Example: Forward dgraph-zero's HTTP port to your host
docker run --rm -it --network host alpine/socat TCP-LISTEN:16080,fork TCP:dgraph-zero:6080
# Now access http://localhost:16080 from your host
```

These techniques let you debug, inspect, or interact with internal-only services without changing your Compose files.

</details>

**How to access services:**

* **From your host (browser or curl):**
  * Dgraph Ratel UI: [http://localhost:8000](http://localhost:8000)
  * Dgraph GraphQL API: [http://localhost:8080/graphql](http://localhost:8080/graphql)
  * Dgraph DQL API: [http://localhost:8080](http://localhost:8080)

* **From inside a Docker container on `dgraph-net`:**
  * Use service names: `dgraph-alpha:8080`, `dgraph-zero:5080`, `dgraph-ratel:8000`

* **From inside a Docker container on `graphtastic_net`:**
  * Use service names: `dgraph-alpha:8080`, `dgraph-ratel:8000`
  * `dgraph-zero` is **not** available on this network for security/isolation.

**Why this matters:**

* Only the API and UI endpoints you need are exposed to the host and other stacks. All cluster-internal traffic (e.g., Zero <-> Alpha) is isolated for security and reliability.

**Example: Accessing Dgraph from another container**

If you have a service on `graphtastic_net` (e.g., a Mesh gateway), you can connect to Dgraph Alpha at `dgraph-alpha:8080`.

If you are running a script inside the `dgraph-net` network, you can use the same service names, but only `dgraph-alpha` and `dgraph-ratel` are reachable from the external network.

This project uses a modular, multi-stack Docker Compose architecture orchestrated by a central `Makefile` to provide a simple and consistent developer experience.

### 3.1. Prerequisites

* Docker Engine and the Docker Compose CLI plugin
* `make`

### 3.2. Getting Started

**WARNING: this doesn't work yet! (WIP)**

1. **Clone the repository:**

    ```bash
    git clone <this-repo-url>
    cd <this-repo-directory>
    ```

2. **Configure the environment:**
    Copy the example environment file and customize it if necessary.

    ```bash
    cp .env.example .env
    ```

3. **Launch the full stack:**
    This single command will create the shared Docker networks and volumes, then bring up the Dgraph cluster, the API service, and any other required components in the correct order.

    ```bash
    make up
    ```

4. **Verify the services:**
    * **Dgraph Ratel UI:** [http://localhost:8000](http://localhost:8000)
    * **Dgraph GraphQL Endpoint:** [http://localhost:8080/graphql](http://localhost:8080/graphql)

5. **Ingest SBOMs and Run the ETL Pipeline**

To ingest SBOMs and load them into Dgraph, follow these steps:

**Step 1: Place your SBOM files**

Copy your SBOM files (e.g., `.spdx.json`, `.cyclonedx.json`) into the `./sboms` directory:

```bash
cp /path/to/your/sbom1.spdx.json ./sboms/
cp /path/to/your/sbom2.cyclonedx.json ./sboms/
```

**Step 2: Ingest SBOMs into GUAC**

Run the following command to ingest all SBOMs in the `./sboms` directory:

```bash
make ingest-sboms
```

**Step 3: Wait for GUAC to finish processing**

Monitor the GUAC containers to ensure ingestion is complete. You can check logs with:

```bash
docker compose -f compose/guac.yml logs -f guac-collectd guac-api guac-graphql
```

Once logs indicate processing is finished (or after a reasonable wait), proceed.

**Step 4: Export data from Mesh to RDF (N-Quads)**

Run the extractor script to pull data from the Mesh GraphQL gateway and generate RDF N-Quads:

```bash
make extract
```

This will create a compressed RDF file in `./build/guac.rdf.gz`.

**Step 5: Seed Dgraph with the extracted RDF**

The full pipeline (including all steps above) can be run with:

```bash
make seed
```

This will clean the environment, bring up all services, ingest SBOMs, extract RDF, and (when implemented) load into Dgraph.

---

6. **Tear down the environment:**
To stop all containers and remove the Docker network, run:

```bash
make down
```

7. **Perform a full cleanup:**
To stop containers and **permanently delete all persistent data**, run:

```bash
make clean
```

## 4. Project Documentation & Design Philosophy

This repository is not just a collection of code; it is a curated set of architectural patterns and design documents that form our engineering standard. The following documents are essential reading for any contributor to understand not just the "how," but the "why" behind our approach.

### 4.1. Platform Architecture & Philosophy

To understand how this subgraph fits into the larger ecosystem, we highly recommend reading the core Graphtastic Platform documentation.

| Document                                                                                               | Description                                                                                                                                                                                                                                                                                             |
| :----------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [Graphtastic Platform README](https://github.com/graphtastic/platform/blob/main/README.md)             | The main entry point for the entire Graphtastic Platform. It outlines the vision of a unified supergraph composed of independent **Spokes**, the central role of the `Makefile` **developer control plane**, and our documentation philosophy centered on **Tomes**. This is the best place to start! |
| [Tome: Graphtastic Platform Docker Compose](https://github.com/graphtastic/platform/blob/main/docs/design/tome--graphtastic-platform-docker-compose.md) | The formal design "Tome" that details the architectural principles and conventions for our multi-stack Docker Compose environments. It explains the "why" behind the modular setup detailed in our practical guides, ensuring every Spoke provides a consistent and seamless developer experience.         |

### 4.2. Core Architectural Designs

| Document                                           | Description                                                                                                                                                                                            |
| :------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`design--guac-to-dgraph.md`](./design--guac-to-dgraph.md) | The definitive implementation plan for this subgraph. It details the schema analysis, the two-phase ETL pipeline, data deduplication strategies, and the schema augmentation process for Dgraph. |

### 4.3. Development and Operations Guides

| Document                                                              | Description                                                                                                                                                                                     |
| :-------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`on--dgraph-docker-compose.md`](./on--dgraph-docker-compose.md)                 | A comprehensive guide to our production-ready Dgraph cluster setup using Docker Compose, detailing the roles of Zero, Alpha, and Ratel, and our strategy for persistent storage.                |
| [`on--running-multiple-docker-compose-stacks.md`](./on--running-multiple-docker-compose-stacks.md) | The architectural blueprint for our modular local development environment. It explains why we avoid monolithic Compose files and how we implement shared networking and storage across stacks. |

### 4.4. GraphQL Primers

| Document                                                                | Description                                                                                                                                                                                                                               |
| :---------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`on--object-identification-in-graphql.md`](./on--object-identification-in-graphql.md) | An in-depth report on the **Global Object Identification (GOI)** specification. This is essential reading to understand how we enable client-side caching, data refetching, and federation via unique `id` fields. |
| [`on--node-union-antipattern.md`](./on--node-union-antipattern.md)                 | A critical analysis of why our schema consistently prefers **`interface`** types over `union` types for modeling polymorphic collections of entities, a decision crucial for schema evolvability and maintainability.        |

## 5. Contributing

Contributions are welcome! Please see our contributing guidelines for more information on how to get involved.

## Licensing

This project is dual-licensed to enable broad code adoption while ensuring our documentation and knowledge base remain open for the community. Project copyright and contributor attribution are managed in our [`NOTICE`](./NOTICE) and [`CONTRIBUTORS.md`](./CONTRIBUTORS.md) files.

* **Code is licensed under [Apache 2.0](https.www.apache.org/licenses/LICENSE-2.0).** This permissive license allows free use in both open-source and commercial products. The full license text is in [`LICENSE.code`](./LICENSE.code).

* **Documentation is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).** This requires **Attribution** for our contributors and that derivative works are shared back under the same **ShareAlike** terms. The full license text is in [`LICENSE.docs`](./LICENSE.docs).
