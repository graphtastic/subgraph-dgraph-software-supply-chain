# Architecting a Production-Ready Dgraph Environment with Docker Compose

This document provides a comprehensive methodology for deploying and managing the Dgraph graph database using Docker Compose. The focus is on establishing a resilient, high-performance local development environment that mirrors production best practices, facilitates rapid iteration, and provides transparent management of configuration and persistent storage. The provided architecture and recommendations are specifically tailored to support demanding applications, such as large-scale social networks.

## Architecting a Resilient Dgraph Cluster with Docker Compose

### Introduction: Moving beyond the standalone image

Initial exploration of Dgraph often begins with the `dgraph/standalone` Docker image, a convenient tool for quick demonstrations. However, this all-in-one image, which bundles Dgraph Zero and Alpha processes into a single container, is explicitly designated as unsuitable for production environments and, by extension, for any serious development or testing workload. Relying on this image introduces significant architectural compromises, including a lack of service isolation, an inability to scale components independently, and opaque resource management. Furthermore, historical inconsistencies regarding the inclusion of the Ratel UI have created confusion and demonstrated the brittleness of such a monolithic approach.

We start with a production-like architecture from the outset. This involves a multi-service deployment where each component of the Dgraph cluster is managed as a distinct, containerized service. We will use docker compose initially to facilitate CI workflows as well as local iterative development, then generate kubernetes manifests. This approach ensures that the development environment accurately reflects the behavior and operational characteristics of a production deployment from the outset of the effort.

### The Core Components of a Dgraph Cluster

A standard Dgraph cluster is composed of three primary, independent components that work in concert:

**TODO: diagram**

*   **Dgraph Zero: The Cluster Coordinator**
    Dgraph Zero serves as the control plane of the cluster. Its responsibilities include managing cluster metadata, distributing data shards (known as tablets) across Alpha nodes, and maintaining cluster-wide consensus using the Raft protocol. It orchestrates leader elections within replica groups and acts as the central authority for transaction timestamp assignment. Zero communicates with Alpha nodes over a gRPC port (default `5080`) and exposes an HTTP endpoint for administrative and metrics purposes (default `6080`).
*   **Dgraph Alpha: The Data Workhorse**
    Dgraph Alpha is the data plane of the cluster. It is responsible for storing the graph data itself, including nodes, edges (stored in posting lists), and indexes. Alpha nodes execute all client queries and mutations, manage transaction logic, and serve data over both gRPC (default `9080`) and HTTP (default `8080`). The GraphQL API layer is an integral part of the Alpha node, making it the primary entry point for application interactions. Alphas are critically dependent on Zero nodes for cluster membership information and transaction coordination.
*   **Dgraph Ratel: The Visual Interface**
    Ratel is an essential administrative and development tool that provides a graphical user interface for interacting with the Dgraph cluster. It allows engineers to execute DQL and GraphQL queries, perform mutations, visualize graph data, and manage the database schema. Ratel is a standalone web application delivered via its own Docker image, `dgraph/ratel`. It operates entirely client-side in the user's browser, connecting to the public HTTP endpoint of a Dgraph Alpha node (port `8080`) to perform its functions.

### Why Docker Compose is the Ideal Tool for Development

Docker Compose is a tool for defining and running multi-container Docker applications through a declarative YAML file. It is the ideal choice for orchestrating a local Dgraph cluster for several reasons. It codifies the entire multi-service architecture—including services, networking, and storage volumes—into a single, version-controllable `docker-compose.yml` file. This practice, a form of "Infrastructure as Code," ensures that every developer on a team can spin up an identical, reproducible environment with a single command. This declarative approach abstracts away the complexity of imperative `docker run` commands with their numerous flags and network configurations, resulting in a cleaner, more manageable, and less error-prone setup.

## The Definitive Docker Compose Configuration for Dgraph

This section presents a complete, annotated Docker Compose configuration designed for stability, persistence, and ease of management.

### Foundational Directory Structure

A well-organized directory structure is crucial for managing persistent data and configuration files. This structure isolates all Dgraph-related assets and aligns with the volume mappings defined in the `docker-compose.yml` file. Before proceeding, create the following directory structure in your project's root:

**TODO ensure is wrapped into the makefile, and located in .graphtastic or somesuch**

```bash
mkdir -p dgraph-stack/dgraph/zero
mkdir -p dgraph-stack/dgraph/alpha
mkdir -p dgraph-stack/config
```

This structure creates separate directories for Zero and Alpha data, preventing state corruption that can occur when services share volumes or when volumes persist incorrectly between different cluster instantiations.

### The Complete docker-compose.yml

This configuration defines the three core services, persistent volumes, and a dedicated network for inter-service communication.

**TODO: use external network**

```yaml
version: "3.8"

services:
  zero:
    image: dgraph/dgraph:latest
    container_name: dgraph_zero
    volumes:
      - ./dgraph-stack/dgraph/zero:/dgraph
    ports:
      - "5080:5080"
      - "6080:6080"
    restart: on-failure
    command: dgraph zero --my=zero:5080
    networks:
      - dgraph-net

  alpha:
    image: dgraph/dgraph:latest
    container_name: dgraph_alpha
    volumes:
      - ./dgraph-stack/dgraph/alpha:/dgraph
      # The config volume will be used in Section 3
      # - ./dgraph-stack/config/start-alpha.sh:/usr/local/bin/start-alpha.sh
    ports:
      - "8080:8080"
      - "9080:9080"
    restart: on-failure
    command: dgraph alpha --my=alpha:7080 --zero=zero:5080
    depends_on:
      - zero
    networks:
      - dgraph-net

  ratel:
    image: dgraph/ratel:latest
    container_name: dgraph_ratel
    ports:
      - "8000:8000"
    restart: on-failure
    networks:
      - dgraph-net

networks:
  dgraph-net:
    driver: bridge
```

### Services

*   **The `zero` Service:**
    *   `image: dgraph/dgraph:latest`: Uses the official, unified Dgraph image for the cluster components.
    *   `volumes:./dgraph-stack/dgraph/zero:/dgraph`: Maps the dedicated host directory for Zero's persistent state into the container. Zero primarily writes to a `zw` subdirectory here, containing its write-ahead logs.
    *   `ports`: Exposes port `5080` for Alpha-to-Zero communication and `6080` for its HTTP/metrics endpoint.
    *   `command: dgraph zero --my=zero:5080`: This command instructs the container to start a Zero process. The `--my` flag is critical; `zero:5080` becomes the addressable name of this service *within the Docker network*, leveraging Docker's internal DNS for service discovery.
*   **The `alpha` Service:**
    *   `volumes:./dgraph-stack/dgraph/alpha:/dgraph`: Maps a *separate* host directory for Alpha's data. This isolation is paramount to prevent data corruption. Alpha stores the primary graph data and indexes in the `p` directory and its write-ahead logs in the `w` directory within this volume.
    *   `ports`: Exposes port `8080` for the HTTP/GraphQL API and `9080` for the gRPC API.
    *   `command: dgraph alpha --my=alpha:7080 --zero=zero:5080`: Starts an Alpha process. `--my=alpha:7080` sets its own address, and `--zero=zero:5080` tells it how to discover the Zero service using its service name. This reliable discovery mechanism avoids common networking issues associated with using `localhost` or hardcoded IP addresses.
*   **The `ratel` Service:**
    *   `image: dgraph/ratel:latest`: Uses the dedicated Ratel image, which is the correct practice as Ratel is no longer bundled with other images.
    *   `ports`: Exposes port `8000`, the default for the Ratel UI, to the host machine.

### Persistent Storage Strategy: A Deep Dive

The configuration uses Docker bind mounts, directly mapping host directories into the containers. This strategy was chosen to satisfy the requirement for data to be easily visible and manageable on the local filesystem, offering greater transparency than Docker-managed named volumes. The table below details the purpose of each persistent directory.

| Host Path                     | Container Path | Service | Internal Directories | Purpose                                                                                                                              |
| :---------------------------- | :------------- | :------ | :------------------- | :----------------------------------------------------------------------------------------------------------------------------------- |
| `./dgraph-stack/dgraph/zero`  | `/dgraph`      | `zero`  | `zw`                 | Stores Zero's Raft write-ahead logs and cluster state. Critical for cluster membership and transaction coordination.                 |
| `./dgraph-stack/dgraph/alpha` | `/dgraph`      | `alpha` | `p`, `w`, `x`        | Stores Alpha's posting lists (`p`, the graph data/indices), Raft WALs (`w`), and live loader mappings (`x`). This is the core database data. |

### Networking (external)

**TODO update to selectively use both default networking, and optionally to participate in an external network to facilitate construction via multiple compose files**

A custom bridge network, `dgraph-net`, is defined and attached to all services. This is a Docker best practice that creates an isolated network for the application. Within this network, Docker provides automatic service discovery, allowing containers to resolve each other by their service name (e.g., the `alpha` container can reach the `zero` container at the hostname `zero`). This makes the `--zero=zero:5080` flag function reliably and renders the entire stack portable across different host machines without any changes to the configuration.

## Externalized Configuration for Rapid Development

Embedding configuration flags directly within the `command` section of the `docker-compose.yml` file is inflexible and hinders rapid iteration. Any change to a flag requires modifying the core infrastructure definition file. To address this, configuration should be decoupled from the service definition.

### Pattern 1: Using Environment Files for Simple Flags

**TODO: use .env.default-rename-me file to make this simpiler, consider wrapping into makefile**

For simple, single-value flags, Docker Compose's support for environment files provides a clean solution. For example, to manage the admin operations whitelist:

1.  Create a file named `.env` in the same directory as your `docker-compose.yml`.
2.  Add the following line to the `.env` file:
    ```ini
    DGRAPH_ALPHA_WHITELIST=0.0.0.0/0
    ```
3.  Modify the `alpha` service's `command` in `docker-compose.yml` to use this variable:
    ```yaml
    command: dgraph alpha --my=alpha:7080 --zero=zero:5080 --security "whitelist=${DGRAPH_ALPHA_WHITELIST}"
    ```

Now, the whitelist can be modified in the `.env` file, and the change can be applied by simply restarting the container.

### Pattern 2: Using Mounted Scripts for Complex Configuration

While not ideal, this pattern is included for reference. We prefer declarative config wherever possible, vs. running scripts. For managing a larger set of configuration flags, a mounted startup script offers maximum flexibility and provides an accessible way to learn CLI commands for dgraph. This pattern moves the entire command logic into an external, version-controllable script.

1.  Create a file named `start-alpha.sh` inside the `./dgraph-stack/config/` directory:
    ```bash
    #!/bin/sh
    # This script allows for complex flag management outside of docker-compose.yml
    # Make this script executable with: chmod +x start-alpha.sh

    dgraph alpha \
      --my=alpha:7080 \
      --zero=zero:5080 \
      --security "whitelist=0.0.0.0/0" \
      --limit "query-edge=1000000; mutations-nquad=1000000;" \
      --telemetry "reports=false; sentry=false;"
    ```
2.  Make the script executable: `chmod +x ./dgraph-stack/config/start-alpha.sh`.
3.  Modify the `alpha` service in `docker-compose.yml` to mount and execute this script:
    ```yaml
    services:
      alpha:
        #... other properties
        volumes:
          - ./dgraph-stack/dgraph/alpha:/dgraph
          - ./dgraph-stack/config/start-alpha.sh:/usr/local/bin/start-alpha.sh
        command: "start-alpha.sh"
        #... other properties
    ```

This approach completely decouples the runtime configuration of the Dgraph Alpha from the Docker Compose definition. Engineers can now freely edit the `start-alpha.sh` file to add or modify any of the extensive command-line flags Dgraph offers and apply them with a simple container restart.

## Cluster Initialization, Schema Management, and Verification

With the architecture defined, the final steps involve launching the cluster, applying an initial schema, and verifying its operation.

### Lifecycle Management with Docker Compose

The following commands are used to manage the Dgraph stack:

*   **Start the cluster:** `docker-compose up -d`. The `-d` flag runs the containers in detached mode, freeing the terminal.
*   **Monitor logs:** `docker-compose logs -f alpha`. Tailing the logs of a specific service is essential for observing its startup process and diagnosing any issues.
*   **Stop and remove containers:** `docker-compose down`. This command stops and removes the containers and the network, but the data in the bind-mounted volumes on the host will persist.
*   **Full reset:** `docker-compose down -v`. This command will also remove any named volumes associated with the stack. For a complete reset with bind mounts, one must manually delete the contents of the `./dgraph-stack/dgraph` directory. This is often necessary to resolve startup issues caused by stale or corrupt state from previous runs.

### Applying the Initial Schema via HTTP API

Before data can be loaded, a schema must be defined to specify predicates, their types, and any desired indexes. Dgraph management is API-driven, and the schema is applied by sending a `POST` request to the Alpha's `/alter` endpoint. This process can and should be automated in real-world projects.

1.  Create a file named `schema.dql` in the `./dgraph-stack/config/` directory. (A sample schema for a social network is provided in the next section).
2.  With the Dgraph cluster running, execute the following `curl` command from your terminal:
    ```bash
    curl -X POST localhost:8080/alter -d @./dgraph-stack/config/schema.dql
    ```
    This command reads the content of `schema.dql` and sends it as the request body. A successful operation will return a JSON response indicating success: `{"data":{"code":"Success","message":"Done"}}`.

### Connecting with Ratel for Verification

The final step is to use Ratel to visually confirm that the entire stack is operational and the schema has been applied correctly.

1.  Open a web browser and navigate to `http://localhost:8000`.
2.  In the Ratel connection modal, ensure the "Dgraph Server URL" is set to `http://localhost:8080`. This points Ratel to the exposed HTTP port of the `alpha` service.
3.  After connecting, navigate to the "Schema" tab on the left-hand sidebar. The predicates and types defined in your `schema.dql` file should be visible.

A successful connection and schema view in Ratel provides a complete end-to-end validation of the architecture, confirming that networking, port mapping, service discovery, and volume persistence are all functioning correctly.

## Strategic Recommendations for a Social Networking Application

The following recommendations provide a starting point for designing a Dgraph-backed social network, focusing on schema design, indexing, and performance.

### Designing a Social Network Graph Schema (DQL)

When modeling for a graph database, the primary focus should be on the entities (nodes) and the rich relationships (edges) between them, rather than on tabular structures. The schema defines not just the data structure, but also the API contract for the application.
Below is a sample `schema.dql` file for a basic social network, which should be placed in `./dgraph-stack/config/schema.dql`.

```dql
# --- Scalar Predicates ---
username: string @index(hash) @upsert .
email: string @index(exact) @upsert .
displayName: string @index(term) .
bio: string .
avatar: string .
createdAt: datetime @index(hour) .
postText: string @index(fulltext) .

# --- UID Predicates (Relationships) ---
author: uid @reverse .
follows: uid @count @reverse .
likes: uid @count @reverse .

# --- Type Definitions ---
type User {
  username
  email
  displayName
  bio
  avatar
  createdAt
  follows
}

type Post {
  postText
  createdAt
  author
  likes
}
```

**Schema Deconstruction:**

*   **`@upsert` Directive:** This is crucial for predicates that must be unique, such as `username` and `email`. It instructs Dgraph to check for conflicts on the indexed value during mutations, preventing duplicates.
*   **`@reverse` Directive:** This directive is fundamental for efficient bidirectional traversal. Defining `author: uid @reverse` allows a query to easily find the author of a post. The automatically created reverse edge, `~author`, allows a query to just as easily find all posts created by a specific user. This is a core advantage of graph models for social data.
*   **`@count` Directive:** This directive instructs Dgraph to maintain a real-time count of the number of edges for a given predicate on a node. This is extremely performant for features like displaying follower counts or like counts, as it avoids expensive traversal and aggregation queries at runtime.

### High-Performance Indexing Strategy

Proper indexing is the most critical factor for query performance in Dgraph. A query that filters on an un-indexed predicate will result in a full scan, leading to poor performance. The choice of index type must align with the intended query patterns.

| Predicate   | Data Type  | Recommended Index | Query Use Case / Application Feature                                                                 |
| :---------- | :--------- | :---------------- | :--------------------------------------------------------------------------------------------------- |
| `username`  | `string`   | `hash`            | **Profile Lookup:** Fast, case-sensitive exact match for `eq(username, "jane.doe")`.               |
| `displayName` | `string`   | `term`            | **User Search:** Keyword-based, case-insensitive search using `anyofterms(displayName, "Jane Doe")`. |
| `email`     | `string`   | `exact`           | **Uniqueness & Sorting:** Required for `@upsert`. The `exact` index also enables sorting and range queries. |
| `postText`  | `string`   | `fulltext`        | **Content Search:** Advanced, language-aware search with stemming and stop-word removal using `alloftext(postText, "graph databases")`. |
| `createdAt` | `datetime` | `hour`            | **Timelines/Feeds:** Efficient filtering and sorting of posts by time ranges, e.g., `ge(createdAt, "2024-01-01")`. |

### Performance and Scalability Considerations

*   **Write Performance:** For applications with high write volumes, such as social media interactions (likes, follows, posts), it is essential to batch mutations. Sending a single mutation request containing 1,000 new edges is orders of magnitude more efficient than sending 1,000 separate requests. High write pressure can become a bottleneck, particularly due to the coordination required to assign transaction timestamps (`startTS`).
*   **Query Optimization:** As Dgraph does not employ a sophisticated query optimizer, query structure significantly impacts performance. Queries should always start from the most specific entry point possible (e.g., a known user UID) and filter down, rather than starting with a broad scan of all nodes of a certain type.
*   **Horizontal Scaling Architecture:** Dgraph achieves horizontal scaling by sharding data across multiple Alpha groups. The unit of sharding is the predicate. This means all data for a single predicate (e.g., `follows`) must reside within a single Alpha group. For a massive social network, a predicate like `follows` could grow exceptionally large, creating a vertical scaling bottleneck for the group that holds it, as it cannot be split further. This is an advanced architectural consideration that highlights a potential scaling limitation at extreme scale.

## Conclusion

This report has detailed a robust and reproducible methodology for running Dgraph with Docker Compose. By rejecting the simplistic `standalone` image in favor of a well-structured, multi-service architecture, developers can build a local environment that is stable, transparent, and aligned with production best practices.
The core principles of this approach are:

1.  **Explicit Separation of Concerns:** Each Dgraph component (Zero, Alpha, Ratel) runs in its own container with isolated, dedicated persistent storage, preventing state corruption and simplifying debugging.
2.  **Infrastructure as Code:** The entire stack is defined declaratively in a `docker-compose.yml` file, ensuring consistency and reproducibility across all development environments.
3.  **Decoupled and Iterative Configuration:** By externalizing runtime flags into shell scripts or environment files, the configuration of Dgraph is decoupled from the infrastructure definition, enabling a rapid and frictionless development workflow.
4.  **API-Driven Management:** The process of applying a schema via `curl` highlights Dgraph's API-first nature, paving the way for automated database migrations and administration.

For a social networking application, leveraging Dgraph's native graph features through a well-designed schema with directives like `@reverse` and `@count`, combined with a strategic indexing plan, provides a powerful foundation for building high-performance, relationship-centric features that are often complex and slow to implement in traditional relational databases. This methodology provides the architectural soundness required to build, test, and ultimately deploy such a system with confidence.

#### Works cited

1.  hypermodeinc/dgraph: high-performance graph database for real-time use cases - GitHub, https://github.com/hypermodeinc/dgraph
2.  Get Started - Quickstart Guide - Netlify, https://release-v21-03--dgraph-docs-repo.netlify.app/docs/v21.03/get-started/
3.  Docker-compose dgraph/standalone, https://discuss.dgraph.io/t/docker-compose-dgraph-standalone/14635
4.  Dgraph Labs - Docker Hub, https://hub.docker.com/u/dgraph
5.  Getting Started docs say that standalone image contains Ratel, but it doesn't, https://discuss.dgraph.io/t/getting-started-docs-say-that-standalone-image-contains-ratel-but-it-doesnt/16767
6.  Top 5 Dgraph Alternatives of 2025 - PuppyGraph, https://www.puppygraph.com/blog/dgraph-alternatives
7.  Dgraph on Kubernetes: Why?. Horizontally Scaling a graph database… | by Joaquín Menchaca (智裕), https://joachim8675309.medium.com/dgraph-on-kubernetes-why-cc7492a0f6f0
8.  Single Host Setup - Dgraph - Hypermode Docs, https://docs.hypermode.com/dgraph/self-managed/single-host-setup
9.  Single Host Setup - Deploy - Netlify, https://release-v21-03--dgraph-docs-repo.netlify.app/docs/v21.03/deploy/single-host-setup/
10. API Endpoints - Dgraph - Hypermode, https://docs.hypermode.com/dgraph/graphql/api
11. Production Checklist - Deploy - Netlify, https://release-v21-03--dgraph-docs-repo.netlify.app/docs/v21.03/deploy/production-checklist/
12. Quickstart - Dgraph - Hypermode Docs, https://docs.hypermode.com/dgraph/quickstart
13. How To Setup Dgraph With Docker On Linux (Ubuntu) - Lion Blogger Tech, https://www.lionbloggertech.com/how-to-setup-dgraph-with-docker-on-linux-ubuntu/
14. dgraph/ratel - Docker Image, https://hub.docker.com/r/dgraph/ratel
15. How to Orchestrate Your Graph Application With Docker Compose - Memgraph, https://memgraph.com/blog/how-to-orchestrate-your-graph-application-with-docker-compose
16. Docker Compose Deployment - Hypermode Docs, https://docs.hypermode.com/dgraph/self-managed/docker-compose
17. How to start dgraph stack locally using compose, https://discuss.dgraph.io/t/how-to-start-dgraph-stack-locally-using-compose/15820
18. Dgraph Zero Docker volume - Users - Discuss Dgraph, https://discuss.dgraph.io/t/dgraph-zero-docker-volume/2152
19. Volumes - Docker Docs, https://docs.docker.com/engine/storage/volumes/
20. Command Reference - Dgraph - Hypermode, https://docs.hypermode.com/dgraph/cli/command-reference
21. Run Dgraph with Docker-Compose - YouTube, https://www.youtube.com/watch?v=BZ84BmtmcW4
22. Errors running dgraph/dgraph:master with Docker Compose, https://discuss.dgraph.io/t/errors-running-dgraph-dgraph-master-with-docker-compose/11981
23. Schema - Query language - Netlify, https://release-v21-03--dgraph-docs-repo.netlify.app/docs/v21.03/query-language/schema/
24. HTTP - Dgraph - Hypermode Docs, https://docs.hypermode.com/dgraph/http
25. Graph Data Models 101 - Dgraph - Hypermode, https://docs.hypermode.com/dgraph/guides/graph-data-models-101
26. Design a Schema for the App - Dgraph - Hypermode, https://docs.hypermode.com/dgraph/guides/message-board-app/graphql/design-app-schema
27. Using Dgraph as your database - DEV Community, https://dev.to/sahilthakur7/using-dgraph-as-your-database-51o7
28. Which side for add the @reverse is better? - Discuss Dgraph, https://discuss.dgraph.io/t/which-side-for-add-the-reverse-is-better/13129
29. Looking for Some Best Practices for Optimizing Queries in Dgraph?, https://discuss.dgraph.io/t/looking-for-some-best-practices-for-optimizing-queries-in-dgraph/19741
30. Optimizing Dgraph Write Performance with Cached startTS, https://discuss.dgraph.io/t/optimizing-dgraph-write-performance-with-cached-startts/19820
31. Mutate performance optimization - Discuss Dgraph, https://discuss.dgraph.io/t/mutate-performance-optimization/5517
32. Advice Needed on Optimizing Dgraph Query Performance - Users, https://discuss.dgraph.io/t/advice-needed-on-optimizing-dgraph-query-performance/19464
33. There are 500 million new tweets everyday. Is dgraph able to scale/shard that volume horizontally? is it true that if a predicate becomes large enough, the only way to deal with that is vertical scaling?, https://discuss.dgraph.io/t/there-are-500-million-new-tweets-everyday-is-dgraph-able-to-scale-shard-that-volume-horizontally-is-it-true-that-if-a-predicate-becomes-large-enough-the-only-way-to-deal-with-that-is-vertical-scaling/16031
