# Subgraph: Dgraph Software Supply Chain

> ## 🚧 **Architectural Blueprints Ahead! 🚀**
>
> Welcome! This repository contains a **work-in-progress** implementation. While the code is still evolving, the architectural and design documentation here represents our north star for building a high-performance, federated graph for software supply chain security. We're excited to have you here and welcome you to explore the designs and join us in the discussions on CNCF Slack in [#initiative-supply-chain-security-insights](https://cloud-native.slack.com/archives/C09A8VBEUNM).

## 1. Overview

This repository contains the source code, operational configuration, and detailed architectural documentation for the `subgraph-dgraph-software-supply-chain`. This service is a foundational ["Spoke"](https://github.com/graphtastic/platform/blob/main/docs/design/tome--graphtastic-platform-docker-compose.md#31-the-hub-and-spoke-model) within the [Graphtastic Platform](https://github.com/graphtastic/platform/blob/main/README.md#the-graphtastic-platform), designed to provide a high-performance, federated GraphQL API for software supply chain security data.

### 1.1. Strategic Goals

This subgraph serves two primary, strategic purposes:

1.  **CNCF Demonstrator:** To act as a reference implementation and standalone demonstrator for the [CNCF Software Supply Chain Insights initiative](https://github.com/cncf/toc/issues/1709).
2.  **Federated Spoke:** To function as a fully compliant, federated Spoke within the Graphtastic supergraph, aggregating and exposing security data from multiple sources.

### 1.2. Core Technology

Our architecture is built on a foundation of powerful, cloud-native technologies:

*   **Data Source:** [GUAC (Graph for Understanding Artifact Composition)](https://guac.sh/) instances, which generate rich software supply chain metadata.
*   **Persistence Layer:** [Dgraph](https://dgraph.io/), a distributed, native GraphQL graph database chosen for its horizontal scalability and high-performance query capabilities.
*   **API Layer:** A GraphQL API designed from the ground up to be compliant with the [Apollo Federation](https://www.apollographql.com/docs/federation/) specification, using [GraphQL Mesh](https://the-guild.dev/graphql/mesh) as a transformation sidecar.
*   **Development Environment:** A modular, multi-stack [Docker Compose](https://docs.docker.com/compose/) environment, orchestrated with `make` for a seamless and reproducible developer experience.

## 2. Local Development

### 2.1. Prerequisites

*   Docker Engine and the Docker Compose CLI plugin
*   `make`
*   `wget` (for the `make fetch-benchmark-data` target)
*   `nc` (netcat, for the `make validate` target)

### 2.2. Getting Started: A Functional Demo in One Command

This repository is configured to provide a complete, end-to-end demonstration of the data pipeline using a 1-million-triple benchmark dataset.

**To launch the entire demo, populate Dgraph with data, and start all services, run:**

```bash
make demo-1m
```

This single command will:
1.  Clean any previous environment.
2.  Create the necessary Docker networks and volumes.
3.  Download the benchmark RDF data.
4.  Run the Dgraph Bulk Loader to ingest the data.
5.  Start the complete, populated application stack.

After the command completes, you can access the services:

*   **Dgraph Ratel UI:** [http://localhost:8001](http://localhost:8001)
*   **Dgraph GraphQL Endpoint:** [http://localhost:8081/graphql](http://localhost:8081/graphql)
*   **GUAC Mesh GraphQL Endpoint:** [http://localhost:4000/graphql](http://localhost:4000/graphql)
*   **GUAC GraphQL Endpoint (raw):** [http://localhost:8080/query](http://localhost:8080/query)

### 2.3. Day-to-Day Workflow

Once the demo is running, or if you want to start an empty environment, use the standard lifecycle commands.

1.  **(First time only) Set up the environment:**
    ```bash
    make setup
    ```
2.  **Launch the stack:**
    ```bash
    make up
    ```
3.  **Validate the running environment:**
    ```bash
    make validate
    ```
4.  **Tear down the environment:**
    ```bash
    make down
    ```
5.  **Perform a full cleanup (deletes all data):**
    ```bash
    make clean
    ```

### 2.4. The Makefile Control Plane

All operational tasks are orchestrated via the Makefile. **Never run `docker` or `docker compose` directly—always use these targets.** Run `make help` for a full list of available commands.

## 3. Architecture

### 3.1. Network Architecture: A Two-Tiered Model

This project employs a deliberate, two-tiered network architecture to ensure both security and modularity. This approach allows each logical stack (like Dgraph or GUAC) to operate in isolation while selectively exposing public-facing APIs on a shared network.

```mermaid
graph TD
    subgraph Host Machine (Your Laptop)
        direction LR
        A["Browser/curl"]
    end

    subgraph Docker Environment
        subgraph Shared External Network (graphtastic_net)
            direction LR
            D[":8081<br/>dgraph-alpha"]
            G[":8080<br/>guac-graphql"]
            M[":4000<br/>guac-mesh"]
            R[":8001<br/>dgraph-ratel"]
            T[fa:fa-wrench Extractor Tool]
        end

        subgraph Dgraph Stack
            direction TB
            D -- "fa:fa-link" --> DZ["dgraph-zero"]
            subgraph Dgraph Internal Network (dgraph_internal_net)
                D <--> DZ
            end
        end

        subgraph GUAC Stack
            direction TB
            G -- "fa:fa-link" --> GP["guac-postgres"]
            subgraph GUAC Internal Network (guac_internal_net)
                G <--> GP
            end
        end
    end

    A -- "http://localhost:8081" --> D
    A -- "http://localhost:8080" --> G
    A -- "http://localhost:4000" --> M
    A -- "http://localhost:8001" --> R

    T -- "http://dgraph-alpha:8080" --> D
    T -- "http://guac-graphql:8080" --> G
    M -- "http://guac-graphql:8080" --> G
```

*   **Internal Networks (`dgraph_internal_net`, `guac_internal_net`):**
    *   **Purpose:** Secure, private communication between the internal components of a single stack.
    *   **Example:** `dgraph-alpha` communicates with `dgraph-zero` over `dgraph_internal_net`. These services are completely inaccessible from outside their stack.
    *   **Analogy:** The private kitchen network in a restaurant.

*   **Shared External Network (`graphtastic_net`):**
    *   **Purpose:** A common network for services that need to expose an API endpoint to other stacks or to the host machine.
    *   **Example:** `dgraph-alpha`, `guac-graphql`, and `guac-mesh-graphql` all attach to this network to expose their APIs. Development tools like the `extractor` also attach here to consume those APIs.
    *   **Analogy:** The public-facing service counter of a restaurant.

This architecture provides the ideal balance: **strong isolation for backend components** and **controlled, discoverable access for public-facing APIs**.

### 3.2. Data Ingestion Flow

For a complete breakdown of the data ingestion architecture, please see the core implementation design:

*   [**`docs/design/design--guac-to-dgraph.md`**](./docs/design/design--guac-to-dgraph.md)

## 4. Project Documentation & Design Philosophy

This repository is not just a collection of code; it is a curated set of architectural patterns and design documents that form our engineering standard. The following documents are essential reading for any contributor to understand not just the "how," but the "why" behind our approach.

| Document                                           | Description                                                                                                                                                                                            |
| :------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`design--guac-to-dgraph.md`](./docs/design/design--guac-to-dgraph.md) | The definitive implementation plan for this subgraph. It details the schema analysis, the two-phase ETL pipeline, data deduplication strategies, and the schema augmentation process for Dgraph. |
| [`on--running-multiple-docker-compose-stacks.md`](./docs/design/on--running-multiple-docker-compose-stacks.md) | The architectural blueprint for our modular local development environment. It explains why we avoid monolithic Compose files and how we implement shared networking and storage across stacks. |
| [`on--object-identification-in-graphql.md`](./docs/design/on--object-identification-in-graphql.md) | An in-depth report on the **Global Object Identification (GOI)** specification. This is essential reading to understand how we enable client-side caching, data refetching, and federation via unique `id` fields. |
| [`on--node-union-antipattern.md`](./docs/design/on--node-union-antipattern.md)                 | A critical analysis of why our schema consistently prefers **`interface`** types over `union` types for modeling polymorphic collections of entities, a decision crucial for schema evolvability and maintainability.        |

## 5. Contributing

Contributions are welcome! Please see our contributing guidelines for more information on how to get involved.

## 6. Licensing

This project is dual-licensed to enable broad code adoption while ensuring our documentation and knowledge base remain open for the community. Project copyright and contributor attribution are managed in our [`NOTICE`](./NOTICE) and [`CONTRIBUTORS.md`](./CONTRIBUTORS.md) files.

*   **Code is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).** The full license text is in [`LICENSE.code`](./LICENSE.code).
*   **Documentation is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).** The full license text is in [`LICENSE.docs`](./LICENSE.docs).