# Disposable local pipeline load test

This dedicated Compose project exercises **real disk-backed MongoDB and RabbitMQ**
and the released event router, monitor, and sequence workers. The CLI runs on the
host; no CLI container image is needed. Synthetic recording events pass through
`monitor,sequence,loadtest-<run-id>`; the CLI consumes the final completion queue.
There is no Vault, video upload, GPU, inference, or notification worker in this
initial mode. This is a functional/local throughput baseline, **not an enterprise
capacity claim** or a substitute for representative full-scale testing.

## Isolation and prerequisites

- Docker Engine with Compose v2 and permission to use its daemon. If access is
  denied, stop: do not use sudo, change socket permissions, or bypass that policy.
- Host Go matching the CLI's `go.mod`, or an existing CLI installation containing
  `load-test`. The commands below assume adjacent `deployment/` and `cli/` checkouts.
- Access to the pinned GHCR images. Private images may require an existing
  authorized Docker registry login; this stack does not obtain credentials.
- Available loopback ports 27028, 5673, and 15673, and disk space for retained data.

The project name is `uug-loadtest`. Its network is private/internal and its named
volumes are project-scoped; no external database, broker, production volume, or
production configuration is mounted. All published ports bind **127.0.0.1 only**.
MongoDB deliberately has no authentication on this isolated local test network.
RabbitMQ's public **disposable test credentials** are
`loadtest` / `disposable-loadtest-only`, not the restricted `guest` account.
Other local processes can access these services: use only synthetic test data.

The released monitor hardcodes database **`Kerberos`**, and the released queue
builders use RabbitMQ's root vhost **`/`**. Consequently, these must be dedicated
instances, not a test database/vhost on shared production infrastructure.
Every CLI invocation below deliberately includes
`--database Kerberos --allow-default-names --run-id smoke`. This safety exception
is appropriate **only for this disposable stack**.

## Start and inspect

From the monorepo root:

```sh
cd deployment/loadtest
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps -a
docker compose images
```

Do not run these daemon commands where Docker access is denied. `config --quiet`
can still validate the manifest without launching containers.

An idempotent init job creates the single-node `loadtest-rs` replica set and waits
for a writable primary. Mongo health checks first verify server availability;
workers start only after the init job succeeds and RabbitMQ is healthy. The init
job refuses to reconfigure an unexpected existing replica set. A successful
`mongo-init` exit is expected, not a failed service. Compose startup is **not**
proof of pipeline readiness: the CLI checks that the required stage queues have
consumers before running.

The host CLI uses `directConnection=true` because the replica advertises
`mongo:27017`, which is resolvable only inside Compose. Workers use that internal
address directly. Both URI configurations request majority reads, journaled
majority writes, and a 10-second write concern timeout. Worker retryable writes
are enabled. A single member exercises replica-set semantics but provides **no
redundancy** and does not model a multi-node majority's latency.

Tracing is deliberately off: `OTEL_SDK_DISABLED=true` and an explicitly empty
`OTEL_EXPORTER_OTLP_ENDPOINT`. The pinned monitor's trace library treats the empty
endpoint as no-op; the pinned sequence ignores its older library's missing-endpoint
error and uses the global no-op provider. No fake collector endpoint or recurring
export failures are needed. Recheck this behavior when overriding worker images.

## Prepare, smoke, and verify

See the [CLI README](https://github.com/uug-ai/cli/blob/main/README.md) for the
load-test command reference.

Fixture preparation is a **separate, untimed step**. Start small: one organisation,
one project, two devices, and no historical recordings. History defaults to zero;
increase `--history-per-device` only when explicitly testing a larger database.
Workload dimensions, rate, duration, concurrency, and deployment label are set
only on `prepare` and frozen in its stored manifest. `run`, `verify`, and `cleanup`
load that manifest by run ID and reject workload overrides.

In the same host shell:

```sh
export LOADTEST_MONGODB_URI='mongodb://127.0.0.1:27028/Kerberos?replicaSet=loadtest-rs&directConnection=true&readConcernLevel=majority&w=majority&journal=true&wtimeoutMS=10000'
export LOADTEST_RABBITMQ_URL='amqp://loadtest:disposable-loadtest-only@127.0.0.1:5673/'
mkdir -p reports
cd ../../cli

# Safe preview: no writes or publication without both execution flags.
go run . load-test prepare \
  --database Kerberos --allow-default-names --run-id smoke \
  --organisations 1 --projects 1 --devices 2 --history-per-device 0 \
  --rate 5 --duration 10s --concurrency 4 --deployment-label local-compose-smoke

# Explicitly seed only this dedicated test target.
go run . load-test prepare \
  --database Kerberos --allow-default-names --run-id smoke \
  --organisations 1 --projects 1 --devices 2 --history-per-device 0 \
  --rate 5 --duration 10s --concurrency 4 --deployment-label local-compose-smoke \
  --execute --confirm-test-target

# First warm/smoke run: 5 events/sec for 10 seconds, 4 publishers.
go run . load-test run \
  --database Kerberos --allow-default-names --run-id smoke \
  --drain-timeout 60s --max-p99 10s \
  --report ../deployment/loadtest/reports/smoke.json \
  --execute --confirm-test-target

go run . load-test verify \
  --database Kerberos --allow-default-names --run-id smoke \
  --execute --confirm-test-target
```

`--max-p99 10s` is a deliberately generous smoke-test gate, not a production SLO.
Let the run drain and inspect verification/report failures before preparing a new
run with increased rate or concurrency. Cleanup retains a manifest tombstone:
use a **new run ID** and prepare new fixtures for each subsequent test, never
reuse an ID after cleanup. There is no automatic cleanup after a run.
Preparation, execution and cleanup share one database-wide lock so their load
cannot overlap. Success releases the active-run lock;
failed or interrupted runs retain it indefinitely to prevent overlap with
unfinished work. Investigate and retain reports first, then reset this dedicated
stack's volumes before starting fresh. A different run ID alone does not bypass
that lock.

The CLI uses **only** `LOADTEST_MONGODB_URI` and `LOADTEST_RABBITMQ_URL` for these
connections, never generic application environment fallbacks. The explicit
`MONGODB_*`/`RABBITMQ_*` entries in Compose are worker settings, not CLI settings.
The `.env.example` lists Compose port/image overrides. If you copy it to `.env`,
Compose reads it automatically, but your host shell does not. Export the CLI URLs
explicitly and change their ports to match `LOADTEST_MONGODB_PORT` and
`LOADTEST_RABBITMQ_PORT`. The management UI is at http://127.0.0.1:15673/ by default;
`LOADTEST_RABBITMQ_MANAGEMENT_PORT` changes that port.

## Results, provenance, and troubleshooting

Record the CLI git revision, fixture dimensions/history, run ID, rate, duration,
concurrency, drain timeout, latency gate, host CPU/RAM/disk, and competing workloads
alongside each report. Record `docker compose images` and
`docker image inspect <image> --format '{{json .RepoDigests}}'` for resolved images;
the defaults are release **tags**, not a claim of immutable image identity or a
known build digest. For reproducible comparisons, retain the resolved digests and
set `LOADTEST_EVENT_IMAGE`, `LOADTEST_MONITOR_IMAGE`, and `LOADTEST_SEQUENCE_IMAGE`
to those immutable references. Pin `LOADTEST_MONGODB_IMAGE` and
`LOADTEST_RABBITMQ_IMAGE` to the resolved digests of MongoDB `8.0.13` and RabbitMQ
`4.1.4-management` as well. Override only with compatible images and record the
change.

From `deployment/loadtest`, inspect `docker compose ps -a` and
`docker compose logs --tail=100 mongo-init event monitor sequence`. If the CLI
reports missing consumers, fix worker startup before retrying. Do not bypass
readiness. `docker compose exec rabbitmq rabbitmqctl list_queues name consumers messages`
can confirm routing and backlog. The worker libraries also declare unrelated
analysis/dead-letter queues; their existence does not mean those workers run.
Do not treat a broker acknowledgement alone as persistence or pipeline completion.

## Explicit cleanup and persistent storage

From `cli/`, first preview and then explicitly remove this run's fixtures:

```sh
go run . load-test cleanup \
  --database Kerberos --allow-default-names --run-id smoke
go run . load-test cleanup \
  --database Kerberos --allow-default-names --run-id smoke \
  --execute --confirm-test-target
```

Wait for a completed/drained run before cleanup. Run-scoped CLI cleanup does not
destroy the shared stage queues or this stack's volumes, and retains a manifest
tombstone so the cleaned run ID cannot be reused. Stop workers before a full reset
if a failed run left messages behind. Cleanup is available only for a finished,
passed run; it does not discard prepared, running,
or failed runs or release their retained active-run lock. The empty, unused
completion queue is retained to preserve late deliveries; it is removed only
when the disposable broker data is explicitly reset.

From `deployment/loadtest`:

```sh
# Stops and removes this stack; retains all database/broker volumes and reports.
docker compose down

# DESTRUCTIVE: only for this dedicated stack. Deletes ALL its persisted test data.
docker compose down --volumes
```

Named volumes persist across stop/start and ordinary `down`; RabbitMQ has a stable
hostname to preserve its on-disk node identity. Reports remain under `reports/`
even after volume reset. Do not prune global Docker resources or reuse these
commands against another Compose project.
