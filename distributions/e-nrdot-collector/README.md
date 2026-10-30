# e-nrdot-collector

| Status    |                                                                                     |
|-----------|-------------------------------------------------------------------------------------|
| Distro    | `e-nrdot-collector`                                                                 |
| Stability | `development`                                                                       |
| Artifacts | Not published yet                                                                   |

NRDOT distribution for infrastructure monitoring together with the New Relic eBPF agent. It ships a curated component set (`manifest.yaml`) and a default configuration that collects host and process metrics and forwards OTLP from the eBPF agent and OBI. Its components are listed in [`component-inventory.yaml`](./component-inventory.yaml); the `eBPF-host` and `eBPF-k8s` tags mark the components our configurations use. Core `nrdot-collector` components left out on purpose are listed, with reasons, in [`excluded-core-components.yaml`](./excluded-core-components.yaml). `make core-drift-check` flags any core component that is in neither file.

Note: See [general README](../README.md) for information that applies to all distributions.

## Platforms

Linux only (`amd64`, `arm64`): Docker image, `deb`/`rpm` packages and `tar.gz` archives. No Windows builds.

## Installation

### Kubernetes

Deployed by the [`nr-ebpf-agent`](https://github.com/newrelic/helm-charts/tree/master/charts/nr-ebpf-agent) Helm chart. The chart renders the full collector configuration (per-node, cluster and control plane) and passes it with `--config`, so the image's default `config.yaml` is not used in Kubernetes.

### Linux hosts

The `deb`/`rpm` packages install the `e-nrdot-collector` systemd service:

| Path | Content |
|---|---|
| `/usr/bin/e-nrdot-collector` | Binary |
| `/etc/e-nrdot-collector/config.yaml` | Default configuration |
| `/etc/e-nrdot-collector/e-nrdot-collector.conf` | Environment file (`OTELCOL_OPTIONS`, license key, …) |
| `/lib/systemd/system/e-nrdot-collector.service` | systemd unit, runs as user `e-nrdot-collector` |

Set `NRDOT_MODE=ROOT` before calling `dpkg`/`rpm` to run the service as root instead.

## Configuration

The default configuration:
- collects host metrics (cpu, load, memory, paging, filesystem, disk, network) and process metrics with the `hostmetricsreceiver`;
- receives OTLP (traces, metrics, logs) from the eBPF agent and OBI on `localhost:4317` (gRPC) and `localhost:4318` (HTTP), keeping the senders' resource attributes;
- exports everything to New Relic via OTLP/HTTP.

It doesn't collect host logs and has no profiles pipeline yet: profiles are an alpha signal that requires the `service.profilesSupport` feature gate. Senders that share the collector's network namespace (same host, or containers in the same Kubernetes pod) reach it on `localhost`. Senders with their own network namespace (another `docker run` container, another pod, another machine) need the receiver endpoints overridden, e.g. `--config 'yaml:receivers::otlp::protocols::grpc::endpoint: 0.0.0.0:4317'`.

| Environment Variable | Description | Default |
|---|---|---|
| `NEW_RELIC_LICENSE_KEY` | New Relic ingest key | N/A - Required |
| `NEW_RELIC_MEMORY_LIMIT_MIB` | Maximum amount of memory to be used | 100 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | New Relic OTLP endpoint, see [official docs](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-otlp/) | `https://otlp.nr-data.net` |
| `OTEL_RESOURCE_ATTRIBUTES` | Extra resource attributes, e.g. `host.id` when it can't be detected | N/A |

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

## Maintaining this distribution

### Files you change

| File | Purpose | When to change it |
|---|---|---|
| `manifest.yaml` | **Source of truth**: the components compiled into the binary | Every component addition or removal |
| `component-inventory.yaml` | One entry per manifest component with the use cases it serves; CI checks it lists exactly the manifest's components | Mirror every manifest change |
| `excluded-core-components.yaml` | Core `nrdot-collector` components deliberately left out, with a reason | When dropping a core component, or when `make core-drift-check` flags a new one |
| `config.yaml` | Default runtime configuration (packages, standalone image). Kubernetes uses the `nr-ebpf-agent` chart's config instead. | When the default behaviour changes |

### Common changes

- **Add a component:**
  1. Add `- gomod: <module> <version>` under its section in `manifest.yaml`. Use the same OTel version as the neighbouring entries to avoid dependency conflicts.
  2. Add `<name>: [<use cases>]` to `component-inventory.yaml`.
  3. If it was listed in `excluded-core-components.yaml`, remove it there.
  4. Wire it into `config.yaml` if it should be on by default.
- **Remove a component:** delete it from `manifest.yaml` and `component-inventory.yaml`. If core still has it, add it to `excluded-core-components.yaml` with the reason.
- **A new component appears in core** (`make core-drift-check` warns): add it as above, or list it in `excluded-core-components.yaml`.
- **After any manifest change:** run `make licenses` (regenerates `THIRD_PARTY_NOTICES.md`) and commit it with the manifest.

### How core changes reach this distribution

The manifest is curated independently of core (not generated from it), so each kind of core change takes a different path:

| Core change | Reaches `e-nrdot-collector` via | Notes |
|---|---|---|
| OTel / NR component version bumps | `.github/workflows/ci-bump-component-versions.yaml` (weekdays) runs `nrdot-collector-builder manifest update` on `distributions/*/manifest.yaml` | Automatic once this distribution is in `newrelic/nrdot-collector-releases`. Modules outside OTel core/contrib, `nrdot-collector-components` and `newrelic-forks` are not bumped (`cmd/nrdot-collector-builder/internal/manifest/config.go`, `getModulePrefix`). |
| CVE fixes (`replaces`) | The `fix-cve` / `cleanup-cve` skills (`.claude/skills/`) edit every `distributions/*/manifest.yaml` that contains the module | Automatic once upstream |
| NRDOT release version (`dist.version`) | `.github/workflows/release-bump-version-pr.yaml` → `scripts/release/bump-nrdot-version.sh` bumps all manifests; `scripts/release/get-version.sh` requires them to match | Automatic |
| Component added to / removed from core | **Not propagated.** `make core-drift-check` flags it | Decide: add to `manifest.yaml`, or list in `excluded-core-components.yaml` |
| Core `config.yaml`, packaging scripts, `Dockerfile` | **Not propagated** (ours are copies) | Review core changes to these files when syncing |

**While working in a fork** (before this distribution is upstream), the automation above only updates core and experimental. After merging upstream changes, align this manifest with core's versions:

```bash
# versions: read them from distributions/nrdot-collector/manifest.yaml
cd cmd/nrdot-collector-builder
go run main.go manifest update --config ../../distributions/e-nrdot-collector/manifest.yaml \
  --core-beta v0.162.0 --core-stable v1.68.0 \
  --contrib-beta v0.162.0 --contrib-stable v1.1.0 \
  --nrdot-version v0.162.1 --nr-fork-contrib-version v0.162.1
```

Copy any new `replaces:` entries from core's manifest by hand, then run `make licenses`.

### Build

Prerequisites: Go (version from `go.mod`), the OpenTelemetry Collector Builder (ocb) at the version of `OTELCOL_BUILDER_VERSION` in the `Makefile`, `yq` (for `make ci`), Docker (for images).

```bash
# one-time: install ocb at the Makefile's OTELCOL_BUILDER_VERSION (0.162.0 at the time of writing)
GOBIN="$HOME/.local/ocb-0.162.0" go install go.opentelemetry.io/collector/cmd/builder@v0.162.0
OCB="$HOME/.local/ocb-0.162.0/builder"

# 1. Linux binary (one arch per run) → distributions/e-nrdot-collector/_build/e-nrdot-collector
GOOS=linux GOARCH=amd64 ./scripts/build/build.sh -d e-nrdot-collector -s false -b "$OCB"

# 2. Validate config.yaml with a native build (a Linux binary doesn't run on macOS)
./scripts/build/build.sh -d e-nrdot-collector -s false -b "$OCB"
NEW_RELIC_LICENSE_KEY=x distributions/e-nrdot-collector/_build/e-nrdot-collector validate \
  --config=distributions/e-nrdot-collector/config.yaml

# 3. After manifest changes
make licenses DISTRIBUTIONS=e-nrdot-collector OTELCOL_BUILDER="$OCB"

# 4. Checks
make core-drift-check DISTRIBUTIONS=e-nrdot-collector
make component-inventory-check DISTRIBUTIONS=e-nrdot-collector   # needs yq
make generate-goreleaser DISTRIBUTIONS=e-nrdot-collector         # only after cmd/goreleaser changes
```

Each `build.sh` run overwrites `_build/e-nrdot-collector`; copy a binary out before building the next one.

### Image

> **TODO (P3): placeholder, not tested yet.** Replace with the verified steps once the image is built and pushed to the selected registry. Don't push to a `newrelic` registry until publishing is approved.

```bash
# build context: the Linux binary (named e-nrdot-collector), config.yaml and the Dockerfile
CTX=$(mktemp -d)
cp distributions/e-nrdot-collector/_build/e-nrdot-collector distributions/e-nrdot-collector/config.yaml \
   distributions/e-nrdot-collector/Dockerfile "$CTX"/
docker buildx build --platform linux/amd64 -t "<REGISTRY>/e-nrdot-collector:<version>-poc.<n>" "$CTX" --push
# local kind cluster instead of a registry:
#   docker buildx build ... --load && kind load docker-image <image> --name <cluster>
```
