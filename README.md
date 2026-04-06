# flink-cdc-ingestion

Real-time Change Data Capture pipeline that streams changes from a PostgreSQL e-commerce database into an Apache Paimon lakehouse using Apache Flink CDC.

## Architecture

```
┌──────────────────┐       ┌───────────────────────────┐       ┌──────────────────┐
│   PostgreSQL     │       │   Embedded Flink Cluster   │       │   Paimon         │
│   (Docker)       │──WAL──│   (runs in your JVM)       │──────▶│   Lakehouse      │
│                  │       │                            │       │                  │
│ port 5432        │       │ Web UI: localhost:8099     │       │ /tmp/paimon-     │
│ wal_level=logical│       │ Checkpointing: 30s        │       │ warehouse/       │
│                  │       │ Parallelism: 2             │       │                  │
└──────────────────┘       └───────────────────────────┘       └──────────────────┘
```

The Flink cluster runs **embedded inside your Java process** (not in Docker). This mirrors how the company project uses `FlinkPipelineComposer.ofApplicationCluster(env)` — the JAR IS the cluster.

### How It Works

1. **PostgreSQL** runs in Docker with `wal_level=logical`, enabling CDC via logical replication
2. **Flink CDC** creates a replication slot and subscribes to changes via `pgoutput`
3. On startup, it performs a **snapshot** (full table scan) of configured tables
4. After snapshot, it switches to **streaming mode** — reading new changes from the WAL in real-time
5. Events are written to **Paimon** tables on the local filesystem as Parquet files
6. **Checkpointing** runs every 30s — each checkpoint creates a new Paimon snapshot

## Prerequisites

- Java 11+ (project compiles to Java 11 target)
- Maven 3.6+
- Docker & Docker Compose

## Quick Start

### 1. Start Postgres

```bash
cd infra
docker compose up -d postgres pgadmin
```

> The Docker Flink containers (jobmanager/taskmanager) are **not needed** — we run Flink embedded.
> To save resources: `docker compose up -d postgres pgadmin`

### 2. Set REPLICA IDENTITY FULL

Required so UPDATE/DELETE events include the full before-image (prevents NPE in Debezium):

```bash
docker exec -e PGPASSWORD=cdc_password postgres-source \
  psql -h localhost -U cdc_user -d ecommerce -c "
    ALTER TABLE ecommerce.orders REPLICA IDENTITY FULL;
    ALTER TABLE ecommerce.customers REPLICA IDENTITY FULL;
  "
```

### 3. Build the uber JAR

```bash
mvn clean package -DskipTests
```

This creates a ~255MB fat JAR with all connectors, Paimon runtime, and Hadoop bundled in. See [Why an uber JAR?](#why-an-uber-jar) below.

### 4. Run the pipeline

```bash
java -cp target/flink-cdc-ingestion-1.0-SNAPSHOT.jar com.learning.cdc.CdcIngestionApp
```

You should see:
```
Starting CDC pipeline from: src/main/resources/yaml_files/ecommerce-pipeline-local.yaml
Parsed pipeline definition
Executing pipeline...
```

### 5. Verify it's working

- **Flink Web UI:** http://localhost:8099
- **Paimon output:**
  ```bash
  ls /tmp/paimon-warehouse/ecommerce.db/
  # orders/  customers/

  ls /tmp/paimon-warehouse/ecommerce.db/orders/snapshot/
  # EARLIEST  LATEST  snapshot-1  snapshot-2  ...
  ```

### 6. Generate live CDC events

```bash
cd infra
./generate-data.sh 10
```

Watch new snapshots appear in the Paimon warehouse as orders flow through the pipeline.

## Project Structure

```
flink-cdc-ingestion/
├── infra/
│   ├── docker-compose.yml              # Postgres + pgAdmin (Flink containers optional)
│   ├── init-db.sql                     # E-commerce schema + seed data
│   └── generate-data.sh               # Simulates order activity via docker exec
├── src/main/
│   ├── java/com/learning/cdc/
│   │   └── CdcIngestionApp.java        # Entry point — embedded Flink + pipeline composer
│   └── resources/
│       ├── yaml_files/
│       │   └── ecommerce-pipeline-local.yaml   # Pipeline definition
│       └── log4j2.xml
└── pom.xml                             # Uber JAR build with shade plugin
```

## Pipeline YAML

```yaml
source:
  type: postgres
  hostname: 127.0.0.1
  tables: ecommerce.ecommerce.orders,ecommerce.ecommerce.customers
  slot.name: flink_cdc_slot_local
  scan.startup.mode: initial        # snapshot first, then stream

sink:
  type: paimon
  catalog.properties.metastore: filesystem
  catalog.properties.warehouse: /tmp/paimon-warehouse
  table.properties.changelog-producer: input
  table.properties.bucket: 4

pipeline:
  name: ecommerce-cdc-local
  parallelism: 2
```

## Paimon Output

```
/tmp/paimon-warehouse/
└── ecommerce.db/
    ├── orders/
    │   ├── schema/                 # Table schema (JSON)
    │   ├── bucket-0/ ... bucket-3/ # Hash-partitioned data
    │   │   ├── data-*.parquet      # Row data
    │   │   └── changelog-*.parquet # CDC changelog
    │   ├── manifest/               # File-to-snapshot mapping
    │   └── snapshot/               # Point-in-time views
    │       ├── EARLIEST / LATEST
    │       └── snapshot-1, 2, 3... # One per checkpoint
    └── customers/
        └── (same structure)
```

## Why an Uber JAR?

The `flink-cdc-pipeline-connector-paimon` fat JAR bundles its own copy of `org.apache.paimon.options.Options`. When Flink's classloader loads this alongside another copy from `paimon-flink-1.20`, the serialize/deserialize cycle crosses classloader boundaries → `ClassCastException`.

The fix (mirroring the company project):

1. Include both connectors as **compile** dependencies (not plugin JARs)
2. Add `paimon-flink-1.20:1.2.0` as the **single source** of Paimon classes
3. **Exclude** `org/apache/paimon/**` from the connector JAR via shade plugin
4. Use `parent-first` classloading + `ofApplicationCluster(env)`

```xml
<!-- Key shade plugin filter -->
<filter>
    <artifact>org.apache.flink:flink-cdc-pipeline-connector-paimon</artifact>
    <excludes>
        <exclude>org/apache/paimon/**</exclude>
    </excludes>
</filter>
```

## Resetting

```bash
# Clean Paimon warehouse
rm -rf /tmp/paimon-warehouse

# Drop replication slot (if pipeline didn't clean up)
docker exec -e PGPASSWORD=cdc_password postgres-source \
  psql -h localhost -U cdc_user -d ecommerce -c \
  "SELECT pg_drop_replication_slot('flink_cdc_slot_local');"

# Restart pipeline — slot is auto-created on startup
```

## Relationship to Company Project

| Aspect | Company Project | This Project |
|--------|----------------|--------------|
| Entry point | `PostgresParallelSourceCdc.java` | `CdcIngestionApp.java` |
| Composer | `ofApplicationCluster(env)` | `ofApplicationCluster(env)` |
| Flink runtime | Amazon Managed Service for Apache Flink | Embedded MiniCluster (port 8099) |
| Paimon runtime | `paimon-bundle:1.4-SNAPSHOT` (provided) | `paimon-flink-1.20:1.2.0` (compile) |
| Paimon sink | Custom overrides (bucket-key, checkpoint tracking) | Upstream defaults |
| Warehouse | S3 (via custom S3FileIO) | Local filesystem |
| Config source | Kinesis Analytics runtime properties | YAML file |
| Password handling | AWS Secrets Manager (`passwordref:`) | Plaintext in YAML |

## Tools

- **Flink Web UI:** http://localhost:8099 — job graph, checkpoints, metrics
- **pgAdmin:** http://localhost:5050 — database browser (admin@admin.com / admin)
- **generate-data.sh** — simulates e-commerce order activity
