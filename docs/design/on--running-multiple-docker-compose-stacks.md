# Architecting Modular and Maintainable Environments with Multiple Docker Compose Stacks

## Section 1: A Primer on Docker Compose for the Modern Engineer

Before architecting complex, multi-stack environments, it is essential to establish a solid foundation in the core principles of Docker Compose. For an engineer new to the tool, understanding its fundamental purpose, its application model, and its basic lifecycle commands is the first step toward mastering more advanced patterns. Docker Compose is a powerful orchestrator for single-host environments, but its default behaviors are designed for encapsulation and isolation. Recognizing this is key to understanding how to deliberately and strategically break that isolation to build interconnected, modular systems.

### 1.1 Introduction to Docker Compose: Orchestration on a Single Host

Docker Compose is a tool designed to define and run multi-container Docker applications. Its primary purpose is to simplify the management of an entire application stack by using a single, declarative YAML configuration file, conventionally named `compose.yaml` or `docker-compose.yml`. This file allows an engineer to define all the components of an application—its services, the networks that connect them, and the volumes that persist their data—and manage their complete lifecycle with a concise set of commands. It is the key to unlocking a streamlined development, testing, and even production workflow on a single Docker host.

The fundamental workflow for using Docker Compose can be distilled into a straightforward three-step process:

1.  **Define the Application Environment:** For any custom components of the application, a `Dockerfile` is created. This file serves as a blueprint, specifying all the dependencies and instructions needed to build a reproducible Docker image for that component.
2.  **Define Services in `compose.yaml`:** In the project's root directory, a `compose.yaml` file is created. This file defines the various services that constitute the application, configuring how they run and interact with one another.
3.  **Run the Application:** With the configuration defined, a single command, `docker compose up`, is used to create, start, and connect all the services, networks, and volumes as a cohesive application stack.

To begin, the host system must have Docker Engine and the Docker Compose CLI plugin installed. Historically, Docker Compose was a separate binary (`docker-compose`), but since the release of Compose V2, it has been integrated directly into the Docker CLI and is invoked as `docker compose`. Modern installations of Docker Desktop for Windows and macOS, as well as standard Docker Engine installations on Linux, include the Compose V2 plugin by default.

### 1.2 The Compose Application Model: Services, Networks, and Volumes

The power of Docker Compose lies in its application model, which abstracts the complexities of container management into three core concepts: services, networks, and volumes.

#### Services

A **service** is an abstract definition of a single, containerized component within the application. It represents a logical piece of functionality, such as a web frontend, a backend API, a database, or a caching layer. Each service is defined by a Docker image (either a pre-existing one from a registry like Docker Hub or one built from a local `Dockerfile`) and a set of runtime configurations. When the application is launched, Docker Compose ensures that one or more containers are created and run according to each service's definition, with all containers for a given service being identical.

For example, a simple web application that tracks page hits might consist of two services: a `web` service running a Python Flask application and a `redis` service for the counter.

```yaml
# compose.yaml
services:
  web:
    build: .
    ports:
      - "8000:5000"
  redis:
    image: "redis:alpine"
```

In this configuration, the `web` service is built from a `Dockerfile` in the current directory, and port `5000` inside the container is mapped to port `8000` on the host machine. The `redis` service simply uses the public `redis:alpine` image from Docker Hub.

#### Networks

By default, when Docker Compose starts an application, it automatically creates a single **bridge network** for that application. Every service defined in the `compose.yaml` file is attached to this network. This is a critical feature, as it provides seamless service discovery and communication. Containers on this network can reach each other by using the service name as a DNS hostname.

Following the previous example, the Python code within the `web` container can connect to the `Redis` service simply by referencing the hostname `redis` on its default port, `6379`, without needing to know the container's internal IP address. This automatic networking simplifies application code and configuration, as the connection details are abstracted away by Compose. The default network is named based on the "project name," which typically defaults to the name of the directory containing the `compose.yaml` file, with a `_default` suffix (e.g., `myapp_default`). This default behavior creates a sandboxed, isolated environment for the application stack. This isolation is the primary architectural characteristic that must be intentionally and explicitly managed to enable the sharing of resources between different stacks, which is the central goal of this report. The challenge is not merely about splitting a configuration file but about strategically connecting these otherwise isolated environments.

#### Volumes

Containers are ephemeral by default; any data written to a container's writable layer is lost when the container is removed. To persist data, Docker provides **volumes**, which are the preferred mechanism for managing persistent data generated by and used by containers. A volume is a directory managed by Docker that is stored on the host machine and mounted into a container. Crucially, a volume's lifecycle is independent of any container's lifecycle; data in a volume persists even after the container using it is deleted.

Docker distinguishes between two primary types of mounts:

*   **Named Volumes:** These are fully managed by Docker via the Docker API. They are created and referenced by a user-defined name. This is the recommended approach for most use cases as it is more portable and decouples the data from the host's filesystem structure.
*   **Bind Mounts:** These map a specific file or directory path from the host machine directly into a container. While useful for development (e.g., mounting source code), they create a tight coupling to the host's directory structure, making the configuration less portable.

In a `compose.yaml` file, named volumes are typically declared at the top level and then attached to services. For instance, a PostgreSQL database service would use a named volume to persist its data files:

```yaml
# compose.yaml
services:
  db:
    image: postgres:13
    volumes:
      - db_data:/var/lib/postgresql/data

volumes:
  db_data:
```

Here, a named volume `db_data` is defined at the top level and then mounted into the `db` service at the path `/var/lib/postgresql/data`. The first time `docker compose up` is run, Docker will create this volume if it doesn't already exist.

### 1.3 Essential Lifecycle Commands

Docker Compose provides a simple command-line interface (CLI) for managing the entire lifecycle of the application stack defined in the `compose.yaml` file.

*   **Bringing the Stack Up:** The `docker compose up` command is the primary command for starting the application. It creates the services, networks, and volumes (if they don't already exist) and starts the containers. By default, it runs in the foreground and streams the logs from all services to the terminal. Using the `-d` or `--detach` flag will start the containers in the background and leave them running.
*   **Bringing the Stack Down:** The `docker compose down` command is the counterpart to `up`. It stops and removes all containers, as well as the network created for the application. A critical point to note is that this command, by default, **does not** remove named volumes. This is a safety feature to prevent accidental data loss. To remove the named volumes along with the containers and network, the `--volumes` or `-v` flag must be explicitly added.
*   **Monitoring and Inspection:** Once the stack is running, several commands are available for inspection. `docker compose ps` lists the containers for the services in the project, showing their current status and port mappings. `docker compose logs` fetches and displays the log output from the services. Appending the `-f` or `--follow` flag will stream the logs in real-time, which is invaluable for debugging.

## Section 2: The Pitfalls of the Monolith: Why a Single Compose File Fails at Scale

While a single `compose.yaml` file is perfect for simple applications, its utility diminishes rapidly as the complexity and scale of an application grow. The user's intuition to avoid a "really messy massive docker compose" is well-founded. Managing a large, multi-component system within a single monolithic configuration file introduces significant technical debt and operational friction, ultimately hindering maintainability, collaboration, and flexibility. The core issue is not merely the file's size but the fact that it imposes a single, unified lifecycle on components that are logically and operationally distinct.

### 2.1 The Maintainability Crisis

As more services are added to a single `compose.yaml` file, it inevitably becomes a source of complexity and confusion.

*   **Cognitive Overhead:** A file with over 20 services can easily span 500 lines or more, making it incredibly difficult for an engineer to read, navigate, and build a mental model of the system. Simple tasks, such as verifying that a host port is not already in use, become a tedious exercise of searching through a massive, unwieldy file. This high cognitive load slows down development and increases the likelihood of errors.
*   **Configuration Drift and Redundancy:** In a large file, it is common for configuration snippets—such as environment variables, volume mounts, logging configurations, or resource limits—to be copied and pasted across multiple service definitions. This violates the "Don't Repeat Yourself" (DRY) principle and leads to configuration drift, where an update is applied to one service but forgotten in another. This redundancy makes the configuration brittle and difficult to maintain. While advanced YAML features like anchors and aliases can mitigate some repetition, they can also introduce their own layer of indirection and complexity, making the file harder to understand for those unfamiliar with the syntax.

### 2.2 The Collaboration Bottleneck

In modern software development, especially within a microservices architecture, different teams often have ownership over different services. A monolithic `compose.yaml` file directly conflicts with this model of distributed ownership, creating a central bottleneck for development.

*   **Team Ownership and Merge Conflicts:** When all service definitions reside in one file, it becomes a single point of contention for multiple teams. If the API team needs to add an environment variable at the same time the data science team is adjusting resource limits for a processing service, they will both be modifying the same file. This leads to frequent merge conflicts in version control and requires significant cross-team coordination for even minor changes.
*   **Increased Blast Radius:** A monolithic configuration means that all components share the same fate. A small syntax error or a misconfiguration in one service definition can prevent the entire application stack from starting when `docker compose up` is executed. This large "blast radius" means that a mistake made by one team can block the work of all other teams. By separating stacks into logical, independently managed files, the blast radius is minimized. A failure in the "monitoring" stack will not prevent the "API" stack from starting, allowing teams to work with greater autonomy and safety.

### 2.3 Operational Inflexibility

Perhaps the most significant drawback of a monolithic `compose.yaml` is the operational inflexibility it imposes. By defining all services within a single "project," Docker Compose treats them as a single, indivisible unit for most lifecycle operations.

*   **Lifecycle Entanglement:** Different logical parts of an application have different operational needs and cadences for change. For example, one might need to restart the logging services without interrupting the core API and database. With a single file, this is difficult. Commands like `docker compose restart` or `docker compose up --force-recreate` apply to the entire project. While it is possible to target a single service (e.g., `docker compose up -d <service_name>`), this does not address the need to manage logical *groups* of services independently. Splitting the configuration into multiple files is the mechanism to break this shared fate and enable independent lifecycle management for different parts of the application.
*   **Scalability Limitations:** Docker Compose is fundamentally a client-side tool designed for orchestrating containers on a single host; it is not a cluster orchestrator like Kubernetes or Docker Swarm. A monolithic file exacerbates these inherent limitations. For instance, scaling a service that exposes a fixed host port is impossible, as multiple containers cannot bind to the same host port. Furthermore, attempting to scale one part of the application (e.g., adding more API workers) requires a redeployment of the entire configuration file, which is inefficient and unnecessarily disruptive to unrelated services.

## Section 3: The Modular Stack Architecture: A Strategic Approach

To overcome the limitations of a monolithic configuration, the recommended approach is to adopt a modular stack architecture. This involves decomposing the application into logical components, each defined by its own independent Docker Compose file. These individual "stacks" can then be composed together to form the complete environment, communicating through shared, externally managed resources. This strategy not only solves the maintainability issues but also aligns better with microservice principles and team-based ownership.

### 3.1 Defining a "Stack": The Role of the Project Name

In the context of Docker Compose, a "stack" is synonymous with a "project." A Compose project is an isolated environment consisting of the services, networks, and volumes defined in a given `compose.yaml` (or set of merged files). To prevent collisions between different stacks running on the same Docker host, Compose uses a **project name** to namespace all created resources. By default, the project name is derived from the name of the directory containing the `compose.yaml` file. For example, a service named `api` in a project named `my-app` will result in a container named `my-app-api-1`.

To effectively manage multiple, independent stacks, it is crucial to explicitly control the project name rather than relying on the directory name. This provides clarity and prevents unintended resource sharing or conflicts. There are several ways to set a project name, but the most direct and flexible method for managing multiple stacks from a command line or script is the `-p` (or `--project-name`) flag.

The order of precedence for determining the project name is as follows, from highest to lowest:

1.  The `-p` command-line flag.
2.  The `COMPOSE_PROJECT_NAME` environment variable.
3.  The top-level `name:` attribute within the `compose.yaml` file.
4.  The base name of the project directory (the default behavior).
5.  The base name of the current working directory if no configuration file is specified.

For example, the command `docker compose -p my-api-stack -f api/compose.yaml up -d` will launch the services defined in `api/compose.yaml` under the project name `my-api-stack`, creating containers like `my-api-stack-api-1` and a network named `my-api-stack_default`.

### 3.2 Strategies for Composing Multiple Files

Docker Compose provides three primary mechanisms for working with multiple configuration files: merging, extending, and including. The choice between them is a fundamental architectural decision that impacts the modularity, coupling, and maintainability of the overall system.

#### Merging with `-f`

The most direct way to combine files is by specifying multiple `-f` flags on the command line. Compose merges the files in the order they are provided, with configurations in later files overriding or extending those in earlier files. This approach is best suited for applying environment-specific overrides, such as having a base `compose.yaml` with common service definitions and a `compose.prod.yaml` that adjusts settings for production (e.g., removing bind mounts, adding restart policies).

The merging rules are well-defined: single-value keys (like `image` or `command`) are replaced by the value from the later file, while multi-value keys (like `ports` or `expose`) have their lists concatenated. However, this method has a critical limitation for building modular systems from components in different directories: **all relative paths** (for build contexts, `.env` files, or bind mounts) are resolved relative to the location of the *first* file specified in the command. This makes the merging strategy brittle and ill-suited for composing stacks from a monorepo structure.

#### Extending with `extends`

The `extends` keyword allows a service to inherit its configuration from another service, either in the same file or a different one. This creates an inheritance-like relationship, which can be useful for reducing duplication (DRY) by defining a common base service and extending it with specific overrides.

```yaml
# common-services.yml
services:
  base_app:
    image: my-app-base
    environment:
      - COMMON_VAR=true
```

```yaml
# compose.yaml
services:
  web:
    extends:
      file: common-services.yml
      service: base_app
    ports:
      - "8080:80"
```

While powerful, `extends` can create tightly coupled configurations that are difficult to trace and understand, especially with multiple levels of inheritance. Docker's own documentation suggests this approach can introduce complexity and is often less flexible than other methods.

#### Composition with `include` (Recommended Modern Approach)

Introduced in Docker Compose 2.20, the `include` directive is the superior, modern solution for building a single application model from multiple, independent Compose files. It is designed specifically for the use case of composing an application from components managed by different teams or located in different parts of a repository.

The primary advantage of `include` is that it **correctly resolves relative paths for each included file from that file's own directory** before merging the configurations into the main application model. This robust path handling makes it the ideal choice for monorepos. Furthermore, `include` promotes a safer composition model by raising an error if any included files define conflicting resources (e.g., two files defining a service with the same name), which prevents unexpected silent overrides and forces explicit configuration decisions.

This approach embodies a "composition over inheritance" design principle. Each included file is treated as a self-contained, black-box component, leading to more decoupled, resilient, and team-friendly configurations.

| Feature                        | Merging (`-f` flag)                  | `extends` Keyword                                   | `include` Directive                                          |
| :----------------------------- | :----------------------------------- | :-------------------------------------------------- | :----------------------------------------------------------- |
| **Primary Use Case**           | Environment-specific overrides (dev, prod, test). | Sharing common configuration snippets within or across files (DRY). | Composing a single application from multiple, independent component files. **Ideal for monorepos.** |
| **Coupling**                   | Low. Files are loosely coupled, but order matters. | High. Creates an inheritance-like dependency.         | Low. Files are treated as black-box components with explicit dependencies. |
| **Relative Path Handling**     | **Brittle.** All paths are relative to the *first* file in the command. | Converts paths to be relative to the *base* file. Can be confusing. | **Robust.** Paths are resolved relative to *each file's own location* before merging. |
| **Conflict Handling**          | Last file specified silently wins. Can lead to unexpected behavior. | Local overrides win. Can create complex inheritance chains. | **Explicit.** Throws an error if resources conflict, forcing clarity. |
| **Recommendation**             | Suitable for simple environment overrides. | Use with caution; `include` is often a better alternative. | **Recommended modern approach for modular stack architecture.** |

## Section 4: Implementing Shared Networking Across Stacks

With a modular architecture where each logical component is its own stack, the next challenge is to enable communication between them. By default, each Docker Compose project creates its own isolated network. To bridge these isolated stacks, the "external network" pattern is employed, which decouples the network's lifecycle from any single stack and creates a shared communication layer.

### 4.1 The "External Network" Pattern

The core concept of the external network pattern is to create a Docker network manually, outside the control of any specific `compose.yaml` file. Each stack that needs to communicate is then configured to connect to this pre-existing, shared network instead of creating its own default one. This makes the network an independent, first-class citizen of the environment, which multiple stacks can then join.

Architecturally, it is a best practice to create this shared network with a custom, explicit name (e.g., `shared_proxy_net`) using the Docker CLI. An alternative, but less robust, approach is to use the default network of one stack (e.g., `stack-a_default`) and have other stacks connect to it. The former approach is superior because it creates a clean, decoupled contract; all stacks depend on a well-known, independent resource. The latter creates an implicit and brittle dependency, where `stack-b` is coupled to the implementation details (the project name) of `stack-a`. If `stack-a`'s directory is ever renamed, the configuration for `stack-b` will break.

### 4.2 Step-by-Step Implementation

The following steps detail how to create a shared network and configure two separate stacks—a reverse proxy and a backend API—to communicate over it.

#### Step 1: Create the Shared Network

This is a one-time setup action for the environment, performed using the Docker CLI.

*   **Command:** Create a standard bridge network with a descriptive name.

    ```bash
    docker network create my_shared_network
    ```

    This command creates a persistent bridge network that will not be removed when any individual stack is brought down.
*   **Verification:** Confirm that the network was created successfully.

    ```bash
    docker network ls
    ```

    The output should list `my_shared_network` among the available networks. For more detailed information, such as the subnet or connected containers, use the inspect command:

    ```bash
    docker network inspect my_shared_network
    ```

#### Step 2: Configure Stack A (Reverse Proxy) to Use the External Network

Modify the `compose.yaml` file for the first stack (e.g., `proxy/compose.yaml`) to connect to the newly created network.

*   **YAML Configuration:**

    ```yaml
    # proxy/compose.yaml
    services:
      proxy:
        image: nginx:alpine
        ports:
          - "80:80"
        networks:
          - shared_net # Connects this service to the network defined below

    networks:
      shared_net:
        name: my_shared_network
        external: true
    ```

*   **Annotation:**
    *   `services.proxy.networks`: This list attaches the `proxy` service to the network referenced as `shared_net`. A service can be attached to multiple networks if needed.
    *   `networks`: This top-level key is where networks used within the Compose file are defined.
    *   `shared_net`: This is the logical name for the network *within this Compose file*.
    *   `name: my_shared_network`: This is the crucial mapping. It tells Compose that the internal name `shared_net` refers to the actual Docker network named `my_shared_network`.
    *   `external: true`: This is the key directive that instructs Docker Compose *not* to create this network, but to use the existing one. If the network `my_shared_network` does not exist when `docker compose up` is run, Compose will return an error.

#### Step 3: Configure Stack B (Backend API) to Use the Same External Network

Repeat the same network configuration for the second stack's `compose.yaml` file (e.g., `api/compose.yaml`). The `networks` block will be identical.

*   **YAML Configuration:**

    ```yaml
    # api/compose.yaml
    services:
      api:
        build: .
        # No ports exposed to the host; communication is via the shared network
        networks:
          - shared_net

    networks:
      shared_net:
        name: my_shared_network
        external: true
    ```

#### Step 4: Launch and Test Communication

Launch both stacks independently, using distinct project names to ensure their resources are properly namespaced.

*   **Launch Commands:**

    ```bash
    docker compose -p proxy-stack -f proxy/compose.yaml up -d
    docker compose -p api-stack -f api/compose.yaml up -d
    ```

*   **Verification:** Once both stacks are running, services can communicate across stacks using their service names as hostnames, because they are on the same network which provides DNS resolution. To test this, one can execute a command inside the proxy container to reach the API service.
    1.  Find the container name for the proxy: `docker ps`
    2.  Execute a shell inside the proxy container: `docker exec -it <proxy_container_name> sh`
    3.  From inside the container, ping the API service using its service name as defined in `api/compose.yaml`:

        ```bash
        # Inside the proxy container
        ping api
        ```

    A successful ping confirms that the containers are on the same network and can resolve each other's names, validating the shared networking setup. The reverse proxy can now be configured to forward requests to `http://api:<port>`.

## Section 5: Implementing Shared Persistent Storage Across Stacks

Similar to networking, enabling data sharing between services in different stacks requires breaking the default volume isolation. The "external volume" pattern provides a robust and portable way to achieve this. It involves creating a Docker-managed named volume independently and then configuring multiple stacks to mount it, allowing them to share a common persistent data store.

### 5.1 The "External Volume" Pattern

The concept is analogous to the external network pattern. A Docker named volume is created using the Docker CLI, giving it a lifecycle that is completely decoupled from any individual Compose project. Services from different stacks can then be configured to mount this pre-existing, "external" volume, enabling them to read and write to the same data directory.

This pattern is ideal for numerous use cases in a microservices architecture, including:

*   A database container in a data stack writing to a volume that is also mounted by a backup stack for periodic backups.
*   An API service in an API stack writing user-uploaded files to a volume that a CDN or frontend stack reads from to serve the content.
*   Multiple services sharing a common set of configuration files or assets stored in a single volume.

A critical architectural decision is the choice between using an external **named volume** versus a shared **bind mount** (a specific host path). While a bind mount might seem simpler for local development (e.g., mounting `/data/shared` into multiple containers), it tightly couples the entire setup to a specific host filesystem structure. This severely hinders portability and reproducibility, as the configuration will fail on any machine—be it a colleague's laptop or a CI/CD runner—that does not have the exact same directory path. External named volumes, which are managed by the Docker daemon itself, abstract away the physical storage location, making them the superior choice for creating portable, consistent, and environment-agnostic multi-stack applications.

### 5.2 Step-by-Step Implementation

The following steps demonstrate how to create a shared named volume and configure two stacks—a data-producing API and a data-consuming backup service—to use it.

#### Step 1: Create the Shared Volume

This is a one-time setup action for the environment, performed using the Docker CLI.

*   **Command:** Create a Docker-managed named volume.

    ```bash
    docker volume create my_shared_data
    ```

    This command instructs the Docker daemon to create a new volume. The actual data will be stored in a directory within Docker's internal storage area (e.g., `/var/lib/docker/volumes/` on Linux), but this location should be considered an implementation detail and not be interacted with directly.
*   **Verification:** Confirm the volume's existence.

    ```bash
    docker volume ls
    ```

    The output will list `my_shared_data`. To see more details, including its mount point on the host, use the inspect command:

    ```bash
    docker volume inspect my_shared_data
    ```

#### Step 2: Configure Stack A (API Service) to Use the External Volume

Modify the `compose.yaml` for the service that will write data to the shared volume (e.g., `api/compose.yaml`).

*   **YAML Configuration:**

    ```yaml
    # api/compose.yaml
    services:
      api_service:
        build: .
        volumes:
          - shared_data:/app/uploads # Mounts the shared volume into the container

    volumes:
      shared_data:
        name: my_shared_data
        external: true
    ```

*   **Annotation:**
    *   `services.api_service.volumes`: This section mounts the volume into the container. The syntax `- shared_data:/app/uploads` maps the logical volume `shared_data` (defined below) to the `/app/uploads` path inside the container.
    *   `volumes`: This top-level key defines the named volumes used by this Compose file.
    *   `shared_data`: This is the logical name for the volume *within this Compose file*.
    *   `name: my_shared_data`: This maps the internal name `shared_data` to the actual Docker volume named `my_shared_data`.
    *   `external: true`: This critical directive tells Compose that the volume is pre-existing and should not be created. If the volume `my_shared_data` does not exist, Compose will raise an error.

#### Step 3: Configure Stack B (Backup Service) to Use the Same External Volume

Modify the `compose.yaml` for another service that needs to access the same data, such as a backup utility.

*   **YAML Configuration:**

    ```yaml
    # backup/compose.yaml
    services:
      backup_service:
        image: backup-service-image
        volumes:
          - shared_data:/data/to_backup # Mounts the same shared volume

    volumes:
      shared_data:
        name: my_shared_data
        external: true
    ```

    Note that the path inside the container (`/data/to_backup`) can be different from the path used in the API service's container. Both mount points will refer to the same underlying data on the host.

#### Step 4: Launch and Test Data Sharing

Launch both stacks using their respective project names.

*   **Launch Commands:**

    ```bash
    docker compose -p api-stack -f api/compose.yaml up -d
    docker compose -p backup-stack -f backup/compose.yaml up -d
    ```

*   **Verification:** To confirm that the volume is shared, create a file from one container and verify its existence from the other.
    1.  Find the container name for the API service: `docker ps`
    2.  Execute a shell inside the API container: `docker exec -it <api_container_name> sh`
    3.  Inside the API container, create a test file in the mounted directory:

        ```bash
        # Inside the API container
        echo "test data" > /app/uploads/test.txt
        exit
        ```

    4.  Find the container name for the backup service: `docker ps`
    5.  Execute a shell inside the backup container: `docker exec -it <backup_container_name> sh`
    6.  Inside the backup container, check for the existence and content of the file:

        ```bash
        # Inside the backup container
        cat /data/to_backup/test.txt
        ```

    The command should output "test data," confirming that both containers are successfully sharing the same persistent volume.

## Section 6: Managing the Multi-Stack Lifecycle and Best Practices

Architecting a modular system with multiple Docker Compose stacks is only the first step. Effective day-to-day management requires moving beyond the basic `docker compose up` command and adopting practices that embrace the modularity of the environment. This involves targeted CLI operations, handling inter-stack dependencies, robust configuration management, and leveraging wrapper scripts to simplify complex workflows. The operational patterns established for a multi-stack environment are as crucial as the initial configuration.

### 6.1 Targeted Stack Operations with the CLI

The primary benefit of a modular architecture is the ability to manage the lifecycle of each stack independently. This is achieved by consistently using the `-p` (project name) and `-f` (file) flags with standard Docker Compose commands.

*   **Viewing Logs for a Specific Stack:** To tail the logs for only the API stack without being inundated by output from the proxy or data stacks:

    ```bash
    docker compose -p api-stack -f api/compose.yaml logs --follow
    ```

*   **Restarting a Single Stack:** If a configuration change is made to the reverse proxy, only that stack needs to be restarted:

    ```bash
    docker compose -p proxy-stack -f proxy/compose.yaml restart
    ```

*   **Rebuilding and Recreating a Service in a Stack:** To apply code changes that require a new image build for the API service:

    ```bash
    docker compose -p api-stack -f api/compose.yaml up -d --build
    ```

These targeted commands reinforce the core principle of independent lifecycle management, minimizing disruption and allowing teams to operate on their components with autonomy.

### 6.2 Advanced: Managing Inter-Stack Dependencies

A significant limitation of the multi-stack architecture is that Docker Compose's `depends_on` feature **does not work across different projects**. A service in the `api` stack cannot use `depends_on` to wait for a database service in the `data` stack to become healthy. This requires more sophisticated strategies for managing startup order and service readiness.

*   **Solution 1: Application-Level Resilience (Production Best Practice):** The most robust solution is to build resilience directly into the application code. Services should be designed to handle the temporary unavailability of their dependencies. This typically involves implementing a retry loop with exponential backoff when establishing connections to other services like databases or message queues. This approach makes the system resilient to transient failures and restarts, which is essential for production environments.
*   **Solution 2: Scripted Startup Orchestration (Development/CI Solution):** For local development and CI environments where a predictable startup order is desired, a wrapper script can be used to orchestrate the launch sequence. This script explicitly starts stacks in the correct order and can wait for services to become healthy before proceeding.

    ```bash
    #!/bin/bash
    set -e # Exit immediately if a command exits with a non-zero status.

    echo "--- Starting Data Stack ---"
    docker compose -p data-stack -f data/compose.yaml up -d

    echo "--- Waiting for Database to be healthy ---"
    # This loop checks the health status of the database container
    # It requires a HEALTHCHECK to be defined in the data/compose.yaml
    while ! docker compose -p data-stack -f data/compose.yaml ps db | grep -q "healthy"; do
        echo "Database is unhealthy - sleeping"
        sleep 5;
    done
    echo "Database is healthy!"

    echo "--- Starting API and Infra Stacks ---"
    docker compose -p api-stack -f api/compose.yaml up -d
    docker compose -p proxy-stack -f infra/compose.yaml up -d

    echo "--- All stacks are up and running ---"
    ```

    This script enforces the dependency that the data stack must be healthy before the API stack is launched, solving the cross-stack dependency problem at the operational level.

### 6.3 Configuration Management with `.env` Files

To maintain clean and portable `compose.yaml` files, it is a critical best practice to externalize configuration values into `.env` files. This separates environment-specific settings (like ports, image tags, user IDs, or credentials) from the structural definition of the services.

*   **Security:** `.env` files should always be added to the project's `.gitignore` file to prevent sensitive information such as API keys or passwords from being committed to version control. While `.env` files are suitable for development, for production environments, using Docker Secrets is the recommended and more secure method for handling sensitive data.
*   **Shared Configuration:** A common `.env` file at the root of the project can be used to define variables that are shared across multiple stacks, ensuring consistency.

    ```ini
    #.env
    COMPOSE_DOCKER_CLI_BUILD=1
    DOCKER_BUILDKIT=1

    # Shared Resource Names
    SHARED_NETWORK_NAME=my_shared_network
    SHARED_VOLUME_NAME=my_shared_data

    # Image Tags
    API_IMAGE_TAG=latest
    ```

    The `compose.yaml` files can then reference these variables using interpolation:

    ```yaml
    # api/compose.yaml
    networks:
      shared_net:
        name: ${SHARED_NETWORK_NAME}
        external: true
    ```

### 6.4 Simplifying Operations with Wrapper Scripts (Makefile)

The CLI commands required to manage a multi-stack environment can become long, repetitive, and prone to error. A Makefile serves as an excellent tool to create simple, memorable aliases for these complex operations, providing a standardized and self-documenting interface for the entire team.

A well-crafted Makefile is more than a convenience; it is a crucial tool for encoding the operational logic and contracts (like startup order and shared resource management) that Docker Compose itself cannot express across project boundaries. It transforms a series of complex, imperative steps into a simple, declarative command (`make up`), which is the ultimate deliverable for an engineer looking for a robust and easy-to-use system.

*   **Example Makefile:**

    ```Makefile
    # Makefile for managing the multi-stack environment

    .PHONY: help setup up down clean logs-api
    .DEFAULT_GOAL := help

    # Load environment variables from .env file
    include .env
    export

    # Define project names and file paths
    PROXY_PROJECT := proxy-stack
    API_PROJECT   := api-stack
    DATA_PROJECT  := data-stack

    PROXY_COMPOSE_FILE := infra/compose.yaml
    API_COMPOSE_FILE   := api/compose.yaml
    DATA_COMPOSE_FILE  := data/compose.yaml

    help:
    	@echo "Usage: make [target]"
    	@echo "Targets:"
    	@echo "  setup      Create shared network and volume"
    	@echo "  up         Bring up all application stacks in the correct order"
    	@echo "  down       Bring down all application stacks"
    	@echo "  clean      Bring down stacks and remove shared resources"
    	@echo "  logs-api   Tail logs for the API stack"

    setup:
    	@echo "--- Creating shared resources ---"
    	@docker network create $(SHARED_NETWORK_NAME) >/dev/null 2>&1 || true
    	@docker volume create $(SHARED_VOLUME_NAME) >/dev/null 2>&1 || true

    up: setup
    	@echo "--- Bringing up all stacks ---"
    	docker compose -p $(DATA_PROJECT) -f $(DATA_COMPOSE_FILE) up -d
    	docker compose -p $(API_PROJECT) -f $(API_COMPOSE_FILE) up -d
    	docker compose -p $(PROXY_PROJECT) -f $(PROXY_COMPOSE_FILE) up -d
    	@echo "--- All stacks are running ---"

    down:
    	@echo "--- Bringing down all stacks ---"
    	docker compose -p $(PROXY_PROJECT) -f $(PROXY_COMPOSE_FILE) down --remove-orphans
    	docker compose -p $(API_PROJECT) -f $(API_COMPOSE_FILE) down --remove-orphans
    	docker compose -p $(DATA_PROJECT) -f $(DATA_COMPOSE_FILE) down --remove-orphans

    clean: down
    	@echo "--- Removing shared resources ---"
    	@docker network rm $(SHARED_NETWORK_NAME) >/dev/null 2>&1 || true
    	@docker volume rm $(SHARED_VOLUME_NAME) >/dev/null 2>&1 || true
    	@echo "--- Cleanup complete ---"

    logs-api:
    	docker compose -p $(API_PROJECT) -f $(API_COMPOSE_FILE) logs --follow
    ```

*   **Benefits:** This Makefile provides a self-documenting interface (`make help`), ensures that shared resources are created before stacks are started (`up` depends on `setup`), and offers simple commands for complex, multi-step operations, ensuring consistency for all team members.

## Section 7: A Complete Reference Implementation

This final section synthesizes all the preceding concepts into a single, concrete, and practical example. It serves as a blueprint that an engineer can adapt for their own projects, demonstrating a complete multi-stack web application with shared networking and storage, all managed by a central Makefile.

### 7.1 Scenario: A Multi-Stack Web Application

The reference application is composed of three logically distinct stacks:

*   **Component 1: The `infra` Stack:** This stack contains a Caddy reverse proxy. Its role is to be the single entry point for HTTP traffic and route requests to the appropriate backend service.
*   **Component 2: The `api` Stack:** This stack contains a backend API service built with Node.js. It handles business logic and requires a database connection.
*   **Component 3: The `data` Stack:** This stack contains a PostgreSQL database service. Its sole responsibility is data persistence.

These stacks will be interconnected using the following shared resources:

*   **Shared Network (`proxy_net`):** A network that allows the `infra` stack (Caddy) to communicate with the `api` stack (Node.js). The database will be isolated from this network for security.
*   **Shared Volume (`postgres_data`):** A named volume to ensure the data for the PostgreSQL database is persisted across container restarts and stack redeployments.

### 7.2 Directory Structure

A clear and logical directory structure is essential for managing a multi-stack project. Each stack resides in its own directory, containing its `compose.yaml` and any other necessary files like `Dockerfiles` or application source code.

```
/my-app/
├── Makefile
├── .env
├── api/
│   ├── compose.yaml
│   ├── Dockerfile
│   └── src/
│       └── index.js
├── data/
│   └── compose.yaml
└── infra/
    ├── compose.yaml
    └── Caddyfile
```

### 7.3 Annotated Configuration Files

Here are the complete, annotated contents for each configuration file in the project.

#### Shared Environment Configuration (`.env`)

This file, located at the project root, defines variables used across multiple stacks, ensuring consistency.

```ini
#.env
# Shared Resource Names
SHARED_PROXY_NETWORK=proxy_net
POSTGRES_DATA_VOLUME=postgres_data

# Data Stack Configuration
POSTGRES_DB=appdb
POSTGRES_USER=appuser
POSTGRES_PASSWORD=supersecretpassword
```

#### Data Stack (`data/compose.yaml`)

This stack manages only the PostgreSQL database, persisting its data in the shared external volume.

```yaml
# data/compose.yaml
services:
  db:
    image: postgres:14-alpine
    restart: always
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    # No ports exposed to the host; access is via a shared network with the API
    networks:
      - default # The API will connect to this stack's default network

volumes:
  postgres_data:
    name: ${POSTGRES_DATA_VOLUME}
    external: true
```

#### API Stack (`api/compose.yaml`)

This stack defines the Node.js API. It connects to two networks: its own default network to communicate with the database, and the shared proxy network to receive traffic from the reverse proxy.

```yaml
# api/compose.yaml
services:
  api:
    build: .
    restart: always
    environment:
      - DATABASE_URL=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
    depends_on:
      - db # This only works because db is in the same project
    networks:
      - data_default # Connect to the data stack's network
      - proxy_net    # Connect to the shared proxy network

networks:
  data_default:
    name: data-stack_default # Explicitly name the data stack's default network
    external: true
  proxy_net:
    name: ${SHARED_PROXY_NETWORK}
    external: true
```

*Note: This example shows connecting to another stack's default network. While possible, creating a dedicated `api_db_net` is often a cleaner pattern.*

#### Infrastructure Stack (`infra/compose.yaml`)

This stack manages the Caddy reverse proxy, which listens on port 80 and forwards traffic to the `api` service over the shared network.

```yaml
# infra/compose.yaml
services:
  proxy:
    image: caddy:2-alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
    networks:
      - proxy_net

networks:
  proxy_net:
    name: ${SHARED_PROXY_NETWORK}
    external: true
```

#### Caddy Configuration (`infra/Caddyfile`)

```nginx
# infra/Caddyfile
{
    auto_https off
}

:80 {
    reverse_proxy api:3000
}
```

#### Central Makefile

This Makefile at the project root orchestrates the entire lifecycle of the multi-stack application.

```Makefile
# /my-app/Makefile

.PHONY: help setup up down clean logs-api
.DEFAULT_GOAL := help

# Load environment variables from .env file
include .env
export

# Define project names and file paths
INFRA_PROJECT := infra-stack
API_PROJECT   := api-stack
DATA_PROJECT  := data-stack

INFRA_COMPOSE_FILE := infra/compose.yaml
API_COMPOSE_FILE   := api/compose.yaml
DATA_COMPOSE_FILE  := data/compose.yaml

help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  setup      Create shared network and volume"
	@echo "  up         Bring up all application stacks in order"
	@echo "  down       Bring down all application stacks"
	@echo "  clean      Bring down stacks and remove shared resources"
	@echo "  logs-api   Tail logs for the API stack"

setup:
	@echo "--- Creating shared resources ---"
	@docker network create $(SHARED_PROXY_NETWORK) >/dev/null 2>&1 || true
	@docker volume create $(POSTGRES_DATA_VOLUME) >/dev/null 2>&1 || true

up: setup
	@echo "--- Bringing up Data Stack ---"
	docker compose -p $(DATA_PROJECT) -f $(DATA_COMPOSE_FILE) up -d
	@echo "--- Bringing up API Stack ---"
	docker compose -p $(API_PROJECT) -f $(API_COMPOSE_FILE) up -d
	@echo "--- Bringing up Infrastructure Stack ---"
	docker compose -p $(INFRA_PROJECT) -f $(INFRA_COMPOSE_FILE) up -d
	@echo "--- All stacks are running ---"

down:
	@echo "--- Bringing down all stacks ---"
	docker compose -p $(INFRA_PROJECT) -f $(INFRA_COMPOSE_FILE) down --remove-orphans
	docker compose -p $(API_PROJECT) -f $(API_COMPOSE_FILE) down --remove-orphans
	docker compose -p $(DATA_PROJECT) -f $(DATA_COMPOSE_FILE) down --remove-orphans

clean: down
	@echo "--- Removing shared resources ---"
	@docker network rm $(SHARED_PROXY_NETWORK) >/dev/null 2>&1 || true
	@docker volume rm $(POSTGRES_DATA_VOLUME) >/dev/null 2>&1 || true
	@echo "--- Cleanup complete ---"

logs-api:
	docker compose -p $(API_PROJECT) -f $(API_COMPOSE_FILE) logs --follow
```

### 7.4 Walkthrough: From Zero to Running

With the project structured and the Makefile in place, an engineer can get the entire environment running with a few simple commands.

1.  **Clone the Repository:**

    ```bash
    git clone <repository_url> my-app
    cd my-app
    ```

2.  **Bring Up the Entire Application:** The `make up` command will automatically run the `setup` target first to create the shared network and volume, and then bring up all three stacks in the correct order.

    ```bash
    make up
    ```

3.  **Verify and Monitor:** Check the logs for a specific stack to ensure it started correctly.

    ```bash
    make logs-api
    ```

4.  **Tear Down and Clean Up:** The `make clean` command provides a complete teardown, stopping and removing all containers and networks from all stacks, and finally removing the shared network and volume.

    ```bash
    make clean
    ```

This reference implementation provides a robust, maintainable, and scalable pattern for managing complex applications with Docker Compose, successfully avoiding the pitfalls of a monolithic configuration while enabling controlled sharing of essential resources.

#### Works cited

1.  Docker Compose - Docker Docs, https://docs.docker.com/compose/
2.  Introduction to Docker Compose | Baeldung on Ops, https://www.baeldung.com/ops/docker-compose
3.  How Compose works - Docker Docs, https://docs.docker.com/compose/intro/compose-application-model/
4.  The docker-compose.yml file | Divio Documentation, https://docs.divio.com/reference/docker-docker-compose/
5.  Getting started with Docker-compose, a quick tutorial - Geshan's Blog, https://geshan.com.np/blog/2024/04/docker-compose-tutorial/
6.  docker/compose: Define and run multi-container applications with Docker - GitHub, https://github.com/docker/compose
7.  Docker Compose Quickstart - Docker Docs, https://docs.docker.com/compose/gettingstarted/
8.  Docker Compose - What is It, Example & Tutorial - Spacelift, https://spacelift.io/blog/docker-compose
9.  Networking in Compose - Docker Docs, https://docs.docker.com/compose/how-tos/networking/
10. Migrate to Compose v2 - Docker Docs, https://docs.docker.com/compose/releases/migrate/
11. Services | Docker Docs, https://docs.docker.com/reference/compose-file/services/
12. Networks in Docker Compose - Medium, https://medium.com/@triwicaksono.com/networks-in-docker-compose-0943abe3de54
13. Communicating between different docker services in docker-compose - Stack Overflow, https://stackoverflow.com/questions/47648792/communicating-between-different-docker-services-in-docker-compose
14. Docker Compose: Features, Benefits, and Usage Guide - The Knowledge Academy, https://www.theknowledgeacademy.com/blog/docker-compose/
15. Volumes | Docker Docs, https://docs.docker.com/engine/storage/volumes/
16. Use Volumes to Manage Persistent Data With Docker Compose - Kinsta, https://kinsta.com/blog/docker-compose-volumes/
17. How to share data between host and containers using volumes in ..., https://stackoverflow.com/questions/40005409/how-to-share-data-between-host-and-containers-using-volumes-in-docker-compose
18. Define and manage volumes in Docker Compose - Docker Docs, https://docs.docker.com/reference/compose-file/volumes/
19. Need help with sharing volume between containers, docker-compose - Reddit, https://www.reddit.com/r/docker/comments/j6dd3f/need_help_with_sharing_volume_between_containers/
20. Shared volumes in Docker Compose 3 · GitHub, https://gist.github.com/jesugmz/bfe4c447ef7558614805f1f85a2ed867
21. Docker Compose Tutorial - Codecademy, https://www.codecademy.com/article/mastering-docker-compose
22. What does Flag do in Docker Compose? - GeeksforGeeks, https://www.geeksforgeeks.org/devops/flag-do-in-docker-compose/
23. docker-compose file has become too long - Stack Overflow, https://stackoverflow.com/questions/52727542/docker-compose-file-has-become-too-long
24. Docker Compose: Splitting one big yml file, carefully, and what about these extra thoughts, https://www.reddit.com/r/selfhosted/comments/1gyo1lk/docker_compose_splitting_one_big_yml_yml_file/
25. Mastering Docker Compose: Eliminate Redundancy with Anchors, Aliases, and Extensions, https://medium.com/codex/mastering-docker-compose-eliminate-redundancy-with-anchors-aliases-and-extensions-6be9bfbc1209
26. Docker Compose - Share named volume between multiple containers - Stack Overflow, https://stackoverflow.com/questions/44284484/docker-compose-share-named-volume-between-multiple-containers
27. Use multiple Compose files | Docker Docs, https://docs.docker.com/compose/how-tos/multiple-compose-files/
28. Improve Docker Compose Modularity with `include`, https://www.docker.com/blog/improve-docker-compose-modularity-with-include/
29. Should I make a huge docker-compose.yml or multiple ones ? : r/selfhosted - Reddit, https://www.reddit.com/r/selfhosted/comments/qm37vq/should_i_make_a_huge_dockercomposeyml_or_multiple/
30. One large compose file? : r/docker - Reddit, https://www.reddit.com/r/docker/comments/1i32i3z/one_large_compose_file/
31. Orchestrate Containers for Development with Docker Compose - CloudBees, https://www.cloudbees.com/blog/orchestrate-containers-for-development-with-docker-compose
32. Limitations of Compose | Docker Course Labs, https://docker.courselabs.co/labs/compose-limits/
33. Docker compose 'scale' command is not scaling across multiple machines - Stack Overflow, https://stackoverflow.com/questions/35376185/docker-compose-scale-command-is-not-scaling-across-multiple-machines
34. Scaling in Docker Compose with hands-on Examples, https://docker77.hashnode.dev/scaling-in-docker-compose-with-hands-on-examples
35. Specify a project name | Docker Docs, https://docs.docker.com/compose/how-tos/project-name/
36. Configure pre-defined environment variables in Docker Compose, https://docs.docker.com/compose/how-tos/environment-variables/envvars/
37. docker compose | Docker Docs, https://docs.docker.com/reference/cli/docker/compose/
38. Merge | Docker Docs, https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/
39. 10 Best Practices for Writing Maintainable Docker Compose Files ..., https://dev.to/wallacefreitas/10-best-practices-for-writing-maintainable-docker-compose-files-4ca2
40. How to split docker-compose for local and production work? | by ..., https://medium.com/@yasen.ivanov89/how-to-split-docker-compose-for-local-and-production-work-b22e310096bd
41. Extend | Docker Docs, https://docs.docker.com/compose/how-tos/multiple-compose-files/extends/
42. How to Link Multiple Docker Compose Files | by mehdi hosseini - Medium, https://medium.com/@mehdi_hosseini/how-to-link-multiple-docker-compose-files-7250f10063a9
43. Include | Docker Docs, https://docs.docker.com/compose/how-tos/multiple-compose-files/include/
44. Communication between multiple docker-compose projects - Stack ..., https://stackoverflow.com/questions/38088279/communication-between-multiple-docker-compose-projects
45. Communication between multiple docker-compose projects, https://dev.to/iamrj846/communication-between-multiple-docker-compose-projects-223k
46. How to share network (or volume) config between multiple compose ..., https://www.reddit.com/r/docker/comments/1evb8ee/how_to_share_network_or_volume_config_between/
47. Docker Networking - Basics, Network Types & Examples - Spacelift, https://spacelift.io/blog/docker-networking
48. Networking | Docker Docs, https://docs.docker.com/engine/network/
49. How to create and manage Docker networks - Educative.io, https://www.educative.io/answers/how-to-create-and-manage-docker-networks
50. Networks - Docker Docs, https://docs.docker.com/reference/compose-file/networks/
51. How To Create And Use Networks In Docker Compose - Warp, https://www.warp.dev/terminus/docker-compose-networks
52. Share Volume Between Multiple Containers in Docker Compose | Baeldung on Ops, https://www.baeldung.com/ops/docker-share-volume-multiple-containers
53. How do I mount a host directory as a volume in docker compose - Stack Overflow, https://stackoverflow.com/questions/40905761/how-do-i-mount-a-host-directory-as-a-volume-in-docker-compose
54. Shared volume across multiple docker-compose projects [duplicate] - Stack Overflow, https://stackoverflow.com/questions/66042906/shared-volume-across-multiple-docker-compose-projects
55. Docker Volumes - Guide with Examples - Spacelift, https://spacelift.io/blog/docker-volumes
56. Docker Volumes: How to Create & Get Started - phoenixNAP, https://phoenixnap.com/kb/docker-volumes
57. docker volume create - Docker Docs, https://docs.docker.com/reference/cli/docker/volume/create/
58. How to run docker container with external volumes - Codebeamer, https://codebeamer.com/cb/wiki/5713519
59. Support for starting stacks in order; or, cross-stack dependencies; or, merged stacks; or, include another stack · portainer · Discussion #12752 · GitHub, https://github.com/orgs/portainer/discussions/12752
60. Defining your multi-container application with docker-compose.yml - .NET | Microsoft Learn, https://learn.microsoft.com/en-us/dotnet/architecture/microservices/multi-container-microservice-net-applications/multi-container-applications-docker-compose
61. Docker Compose - How to execute multiple commands? - Stack Overflow, https://stackoverflow.com/questions/30063907/docker-compose-how-to-execute-multiple-commands
62. Set environment variables | Docker Docs, https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/
63. Handling Environment Variables in Docker Compose for Secure and Flexible Configurations, https://medium.com/@sh.hamzarauf/handling-environment-variables-in-docker-compose-for-secure-and-flexible-configurations-5ce6a5bb0412
64. Best practices | Docker Docs, https://docs.docker.com/compose/how-tos/environment-variables/best-practices/
65. Started dockermake (create Makefiles for docker/docker-compose) : r/opensource - Reddit, https://www.reddit.com/r/opensource/comments/1auw5fb/started_dockermake_create_makefiles_for/
66. Simplifying docker-compose operations using Makefile | by Khushbu ..., https://medium.com/freestoneinfotech/simplifying-docker-compose-operations-using-makefile-26d451456d63
67. Makefiles and Docker for Local Development | Cody Hiar, https://www.codyhiar.com/blog/makefiles-and-docker-for-local-development/
68. 4 Ways on How To Use Makefile - Jerry Ng, https://jerrynsh.com/4-levels-of-how-to-use-makefile/