# Langfuse v3 to v4 operator runbook

This repository now deploys Langfuse v4 in `dual` write mode. It preserves v3
ingestion and reads while writing observations to the v4 data model. Do not
switch to `events_only` until every project-dependent check below is complete.

## Before deployment

1. Confirm the target self-hosted host and project. Back up PostgreSQL and
   ClickHouse immediately before the server upgrade.
2. On the latest v3 server, confirm every Langfuse background migration has
   completed. In PostgreSQL, `SELECT name, failed_at, failed_reason FROM
   background_migrations WHERE finished_at IS NULL;` must return no rows.
3. Upgrade ClickHouse to 25.12 or newer before starting Langfuse v4. Confirm
   that capacity includes approximately three times the current ClickHouse data
   volume if historic backfill will be used.
4. Grant the configured ClickHouse user the v4 migration permissions:

   ```sql
   GRANT DROP VIEW ON default.* TO 'langfuse';
   GRANT ALTER ADD COLUMN, ALTER MODIFY COLUMN, ALTER VIEW MODIFY QUERY ON default.* TO 'langfuse';
   GRANT ALTER ADD INDEX, ALTER DROP INDEX, ALTER MATERIALIZE INDEX ON default.* TO 'langfuse';
   GRANT SELECT(database, table, name, partition, partition_id, active, rows) ON system.parts TO 'langfuse';
   GRANT SELECT(database, table, is_done) ON system.mutations TO 'langfuse';
   GRANT SELECT(database, name, engine) ON system.tables TO 'langfuse';
   GRANT SELECT ON system.processes TO 'langfuse';
   GRANT SELECT ON system.query_log* TO 'langfuse';
   GRANT SYSTEM SYNC REPLICA, SYSTEM MERGES, ALTER SETTINGS ON default.observations_pid_tid_sorting TO 'langfuse';
   ```

   Replace `langfuse` if the runtime uses another ClickHouse user. Clustered
   deployments also need the documented `READ ON REMOTE` and `CLUSTER` grants.
5. Generate a new protected runtime environment file with
   `scripts/bootstrap-local-llm.sh private/local-llm.env`; do not commit it.
   The script creates the v4 database, authentication, encryption, and MinIO
   credentials. Keep the generated file mode `0600`.

## Deploy and validate dual write

1. Render the compose file with the generated environment file before deploying
   the updated stack:

   ```sh
   RUNTIME_ENV_FILE=private/local-llm.env docker compose \
     --env-file private/local-llm.env \
     -f compose/local-llm-primary.compose.example.yaml config --quiet
   ```

   The v4 worker uses port 3030 only on loopback, and MinIO uses loopback ports
   9090 and 9091.
2. Verify web, worker, PostgreSQL, ClickHouse, Redis, and MinIO are healthy.
   Check the worker endpoint
   `http://127.0.0.1:3030/api/health?failIfEventPropagationStuck=true`; a 503
   indicates stalled dual-write propagation.
3. Send representative non-production LiteLLM requests. In Langfuse, inspect
   the root observation and every applicable child: root input/output belong on
   the root, session/user/tags/release/environment attributes propagate to
   children, and any cost-bearing generation carries the session ID.
4. Inspect Project Settings > Integrations and the Evaluators UI. Migrate each
   active legacy trace evaluator to one observation target, each legacy dataset
   evaluator to an experiment target, and every Blob Storage, Mixpanel, or
   PostHog export to Enriched observations. Create successors disabled, compare
   them on new data, obtain approval, then disable rather than delete legacy
   evaluators.

## Cutover and rollback

Keep `LANGFUSE_MIGRATION_V4_WRITE_MODE=dual` and historic backfill disabled
until the project checks pass. Then either enable the one-time historic
backfill after sizing disk capacity, or retain dual write for a complete data
retention period. Only then remove the migration overrides (or set
`events_only` and direct native OTel behavior).

The v4 schema migration is not reverted by replacing the image with v3. Before
cutover, prefer remaining on v4 with `legacy` or `dual` mode. A true v3
rollback requires the documented ClickHouse schema rewind or restoration of the
pre-upgrade PostgreSQL and ClickHouse backups. Never truncate legacy tables
until historic observations and all downstream consumers have been verified.
