# flink-cdc-ingestion

Real-time Change Data Capture pipeline that streams changes from a PostgreSQL e-commerce database into an Apache Paimon lakehouse using Apache Flink CDC.

## Architecture

```
┌─────────────────┐       ┌──────────────────┐       ┌─────────────────────┐
│   PostgreSQL    │       │   Flink CDC      │       │   Paimon Lakehouse  │
│   (ecommerce)   │──WAL──│   Pipeline       │──────▶│   (filesystem)      │
│                 │       │                  │       │                     │
│ • orders        │       │ • Snapshot phase │       │ • orders            │
│ • order_items   │       │ • Streaming phase│       │ • order_items       │
│ • customers     │       │ • Checkpointing  │       │ • customers         │
│ • products      │       │                  │       │ • products          │
│ • payments      │       │                  │       │ • payments          │
│ • inventory     │       │                  │       │ • inventory_events  │
│ • shipments     │       │                  │       │ • shipments         │
└─────────────────┘       └──────────────────┘       └─────────────────────┘
                                                              │
                                                              ▼
                                                     flink-streaming-transforms
                                                     (downstream consumer)
```

### How It Works

1. **PostgreSQL** runs with `wal_level=logical` enabled, which allows Flink CDC to read the Write-Ahead Log
2. **Flink CDC** creates a replication slot and subscribes to changes via a publication
3. On startup, it performs a **snapshot** (full table scan) of all configured tables
4. After snapshot completes, it switches to **streaming mode** — reading only new INSERT/UPDATE/DELETE events from the WAL in real-time
5. Events are written to **Paimon** tables (a lakehouse format optimized for streaming writes and changelog tracking)
6. **Checkpointing** runs every 30s to ensure exactly-once delivery — if the job crashes, it resumes from the last checkpoint

### Pipeline Definition

The pipeline is defined declaratively in a YAML file (`resources/yaml_files/ecommerce-pipeline.yaml`):

```yaml
source:  PostgreSQL (CDC connector with replication slot)
    ↓
transform:  Optional projections/filters on the CDC stream
    ↓
sink:  Paimon (filesystem catalog, bucketed tables, changelog-producer: input)
```

## Quick Start

```bash
# 1. Start infrastructure
cd infra
docker compose up -d

# 2. Verify Postgres is ready
docker exec -it postgres-source psql -U cdc_user -d ecommerce -c "SELECT count(*) FROM ecommerce.customers;"

# 3. Open Flink UI
open http://localhost:8081

# 4. Generate test data (simulates real-time order activity)
chmod +x generate-data.sh
./generate-data.sh 10

# 5. Stop everything
docker compose down -v
```

## Project Structure

```
flink-cdc-ingestion/
├── infra/
│   ├── docker-compose.yml          # Postgres (CDC-enabled) + Flink cluster
│   ├── init-db.sql                 # E-commerce schema + seed data
│   ├── generate-data.sh            # Data generator script
│   └── jars/                       # Custom JARs for Flink cluster
├── src/main/
│   ├── java/com/learning/cdc/      # Application code
│   └── resources/
│       ├── yaml_files/             # CDC pipeline definitions
│       └── log4j.properties
└── pom.xml
```

## Key Concepts

| Concept | Description |
|---------|-------------|
| WAL (Write-Ahead Log) | Postgres transaction log — CDC reads changes from here |
| Replication Slot | Postgres reserves WAL segments so the CDC reader doesn't miss events |
| Publication | Defines which tables Postgres publishes changes for |
| Snapshot Phase | Initial full table scan before switching to streaming |
| Changelog Mode | How updates are encoded — `upsert` (INSERT only) vs `all` (INSERT + UPDATE_BEFORE + UPDATE_AFTER + DELETE) |
| Checkpointing | Periodic state snapshots enabling exactly-once semantics and crash recovery |
| Paimon | Lakehouse table format with native changelog support, optimized for streaming writes |
