# Troubleshooting for e-nrdot-collector

For general NRDOT troubleshooting, see [this guide](../TROUBLESHOOTING.md). This document assumes you are familiar with the troubleshooting tools mentioned.

## Host and process metrics

### Missing host entity in New Relic UI due to missing `host.id`
If you are [seeing telemetry getting ingested into New Relic](../TROUBLESHOOTING.md#telemetry-not-reaching-new-relic) but the Host UI does not show host entities after a few minutes, you may be running into limitations of the [resourcedetectionprocessor](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/resourcedetectionprocessor/README.md) NRDOT uses to determine the `host.id` attribute required to [synthesize a host entity](https://github.com/newrelic/entity-definitions/blob/main/entity-types/infra-host/definition.yml#L62-L63).

Example log messages indicating this issue:
```
# example 1
2025-01-01T22:49:09.110Z        warn    system/system.go:143    failed to get host ID   {"otelcol.component.id": "resource_detection", "otelcol.component.kind" : "Processor", "otelcol.pipeline.id": "logs/host", "otelcol.signal": "logs", "error": "failed to obtain \"host.id\": error detecting resource: host id not found in: /etc/machine-id or /var/lib/dbus/machine-id"}
# example 2
2025-01-01T23:07:27.866Z        warn    system/system.go:143    failed to get host ID   {"otelcol.component.id": "resource_detection", "otelcol.component.kind": "Processor", "otelcol.pipeline.id": "metrics/host", "otelcol.signal": "metrics", "error": "empty \"host.id\""}
```

**Resolution:** Set the `host.id` attribute manually via the [environment variable](./README.md#configuration) `OTEL_RESOURCE_ATTRIBUTES`:
```bash
export OTEL_RESOURCE_ATTRIBUTES='host.id=my-custom-host-id'
```

### No `root_path` in containerized environments
The `hostmetricsreceiver` auto-detects files to scrape system metrics from. When running in a container, this causes the receiver to scrape metrics of the container instead of the host system. The receiver provides the `root_path` option to specify the path where the host file system is mounted into the container.

Warning message indicating this issue:
```
2025-01-01T21:08:21.097Z	warn	filesystemscraper/factory.go:48	No `root_path` config set when running in docker environment, will report container filesystem stats. See https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/hostmetricsreceiver#collecting-host-metrics-from-inside-a-container-linux-only	{"otelcol.component.id": "host_metrics", "otelcol.component.kind": "Receiver", "otelcol.signal": "metrics"}
```

**Resolution:** Follow the [receiver's docs](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/hostmetricsreceiver/README.md#collecting-host-metrics-from-inside-a-container-linux-only) to mount the host file system and configure `root_path`:
```bash
docker run -v /:/hostfs \
-e NEW_RELIC_LICENSE_KEY='license-key' <registry>/e-nrdot-collector \
--config /etc/e-nrdot-collector/config.yaml \
--config 'yaml:receivers::host_metrics::root_path: /hostfs'
```
