# flink-cdc-ingestion

CDC ingestion pipeline: PostgreSQL → Paimon lakehouse using Apache Flink CDC.

Mirrors the architecture of the company `flink-cdc` repo.

## Quick Start

```bash
# 1. Start infrastructure
cd infra
docker compose up -d

# 2. Verify Postgres is ready
docker exec -it postgres-source psql -U cdc_user -d ecommerce -c "SELECT count(*) FROM ecommerce.customers;"

# 3. Open Flink UI
open http://localhost:8081

# 4. Generate test data
./generate-data.sh 10

# 5. Stop everything
docker compose down -v
```

## Project Structure

```
flink-cdc-ingestion/
├── infra/
│   ├── docker-compose.yml      # Postgres + Flink cluster
│   ├── init-db.sql             # Ecommerce schema + seed data
│   └── generate-data.sh        # Simulates real-time order activity
├── src/main/
│   ├── java/com/learning/cdc/  # Your code goes here
│   └── resources/
│       └── yaml_files/         # Pipeline definitions (source → sink)
└── pom.xml
```

## Learning Exercises

### Phase 1: Get Data Flowing
- [ ] Write the main class that loads the YAML and runs the pipeline
- [ ] Verify data appears in Paimon warehouse (`/opt/paimon/warehouse`)
- [ ] Run `generate-data.sh` and watch CDC events flow in real-time

### Phase 2: Expand the Pipeline
- [ ] Add all ecommerce tables to the YAML (orders, order_items, payments, etc.)
- [ ] Add `metadata.list: op_ts` to capture operation timestamps
- [ ] Configure per-table bucket keys (like `bucket-key` in company YAML)

### Phase 3: Understand CDC Internals
- [ ] Check the replication slot: `SELECT * FROM pg_replication_slots;`
- [ ] Monitor WAL lag: `SELECT pg_current_wal_lsn();`
- [ ] Try `scan.startup.mode: latest-offset` vs `initial` — what changes?
- [ ] ALTER a table in Postgres — what happens to the pipeline?

### Phase 4: Production Patterns
- [ ] Add structured logging (mirror CloudWatchLogger pattern)
- [ ] Add config management (dev vs prod YAML files)
- [ ] Handle password externalization (mirror the `passwordref` pattern)

## Key Concepts to Understand

| Concept | What it means | Company repo reference |
|---------|--------------|----------------------|
| Replication slot | Postgres reserves WAL for your CDC reader | `slot.name` in YAML |
| Publication | Which tables Postgres publishes changes for | `debezium.publication.name` |
| Snapshot phase | Initial full table scan before streaming | `scan.startup.mode: initial` |
| Changelog mode | How updates are encoded (all vs upsert) | `changelog-mode: upsert` |
| Checkpointing | Periodic state snapshots for fault tolerance | `env.enableCheckpointing()` |
