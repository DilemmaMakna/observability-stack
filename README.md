# Lemma Observability Stack

[![Grafana](https://img.shields.io/badge/Grafana-v11.1.0-orange?logo=grafana)](https://grafana.com)
[![Prometheus](https://img.shields.io/badge/Prometheus-v2.53.0-red?logo=prometheus)](https://prometheus.io)
[![Loki](https://img.shields.io/badge/Loki-v3.0.0-blue?logo=grafana)](https://grafana.com/oss/loki/)
[![Alloy](https://img.shields.io/badge/Alloy-v1.18.0-blue?logo=grafana)](https://grafana.com/oss/alloy/)
[![Tempo](https://img.shields.io/badge/Tempo-v2.5.0-blue?logo=grafana)](https://grafana.com/oss/tempo/)
[![Docker](https://img.shields.io/badge/Docker-Stack-blue?logo=docker)](https://www.docker.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue)](https://opensource.org/licenses/Apache-2.0)

This repository provides an enterprise grade, resource efficient observability stack designed for production environments. It implements full monitoring of the four golden signals (latency, traffic, errors, and saturation) and establishes OpenTelemetry OTLP ingestion standards for application logs, metrics, and distributed traces.

## Architecture

The stack is composed of the following core systems:

1. Grafana: Visualizes metrics, logs, and traces through centralized dashboards.
2. Prometheus: Collects time series metrics from hosts and containers.
3. Loki: Provides log aggregation using TSDB indexing and local filesystem storage.
4. Grafana Alloy: Exposes OTLP HTTP and gRPC endpoints VM-wide to receive application logs, metrics, and traces.
5. Grafana Tempo: Aggregates and stores distributed traces from microservices and LLM applications.
6. Node Exporter: Exports host level performance statistics (CPU, memory, disk, network).
7. cAdvisor: Gathers container level metrics and resource utilization details.

## Directory Structure

All configurations are modular and decoupled:

```text
observability/
  alloy: Grafana Alloy collector pipeline configuration
  backup: Backup and restore utilities
  dashboards: Preconfigured Grafana dashboards
  grafana: Configuration and provisioning rules
  loki: Log aggregation database settings
  prometheus: Metric scraping and alert rules
  tempo: Grafana Tempo tracing backend configuration
```

## Deployment

### Prerequisites

1. Docker Engine and Docker Compose V2.
2. Target user must be a member of the docker group.

### Step 1: Environment Setup

Create the environment file from the template:

```bash
cp .env.example .env
```

Open `.env` to configure version tags, port numbers, and database retention policies. Ensure you change the default Grafana admin password before deploying.

### Step 2: Launch Stack

Deploy the stack in detached mode:

```bash
docker compose up -d
```

### Step 3: Access Ports

1. Grafana: `http://localhost:3030` (Default credentials: admin / your password)
2. Grafana Alloy UI: `http://localhost:12345` (Collector health and pipeline graph status)
3. OTLP gRPC Endpoint: Port `4317` (Used by applications to send traces, metrics, and logs)
4. OTLP HTTP Endpoint: Port `4318` (Alternative OTLP HTTP push endpoint)

### Deployment on Dokploy

This stack is production ready for Dokploy deployment using Traefik:

1. Create a Docker Compose application in your Dokploy panel.
2. Connect your Git repository.
3. Configure domains for your services using the Dokploy UI. Map your Grafana domain to the `grafana` service on container port `3000`. Map your OTLP endpoints to `alloy` on ports `4317` and `4318`.
4. Deploy the stack. Dokploy handles the Traefik routing, TLS certificate generation, and network isolation automatically.

## Log and Trace Correlation

The Loki pipeline integrates with Tempo through derived fields to automatically link logs to traces. 

1. Regex Extraction: The Loki data source uses the expression `trace_id[=:\s"]+(\w+)` to parse trace identifiers from logs.
2. Direct Navigation: Clicking the View Trace button next to a log line opens the Tempo trace timeline split-screen instantly.
3. Trace-to-Logs: When viewing a trace, you can search corresponding logs for that specific trace or span with one click.

## Running the SRE AI Test Application

An SRE test application is provided in `test_ai.py` to verify the end-to-end flow of logs, metrics, and traces. To run it locally on the host:

```bash
uv run --with python-dotenv --with openai --with opentelemetry-api --with opentelemetry-sdk --with opentelemetry-exporter-otlp --with opentelemetry-instrumentation-openai python test_ai.py
```

This script performs the following actions:
1. Connects to OpenAI using your API key from the local `.env`.
2. Generates traces and logs structured under the OpenTelemetry GenAI Semantic Conventions.
3. Flushes the telemetry directly to Alloy, which routes them to Loki and Tempo.

## Resource Allocation and Limits

To support deployment on small hosts, CPU and memory boundaries are set on every container:

1. Prometheus: Limited to 1200MB memory, 1.00 CPU. Retention set to 14 days or 10GB.
2. Loki: Limited to 1000MB memory, 1.00 CPU. Retention set to 7 days.
3. Grafana: Limited to 400MB memory, 0.50 CPU.
4. Grafana Alloy: Limited to 250MB memory, 0.50 CPU.
5. Grafana Tempo: Limited to 400MB memory, 0.50 CPU.
6. cAdvisor: Limited to 150MB memory, 0.40 CPU.
7. Node Exporter: Limited to 50MB memory, 0.20 CPU.

The total memory reservation is optimized for a 4GB RAM instance, leaving a safe buffer.

## Backup and Disaster Recovery

A shell script handles automated volume state archiving.

### Executing a Backup

Run the utility:

```bash
./backup/backup.sh
```

The backup workflow performs these steps:

1. Compresses configuration directories and the `.env` file into a configuration archive.
2. Mounts active Docker volumes in read only mode to a temporary container to generate database archives.
3. Stores all compressed files under the backup directory.
4. Applies a 7 day retention window, deleting older files.

### Restoring a State

To restore the stack:

1. Unpack the configuration files:
   ```bash
   tar -xzf backup/archive/config_timestamp.tar.gz -C /home/ubuntu/lemma/observability-stack
   ```

2. Provision the Docker volumes:
   ```bash
   docker volume create lemma_prometheus_data
   docker volume create lemma_loki_data
   docker volume create lemma_grafana_data
   docker volume create lemma_tempo_data
   ```

3. Unpack database contents back into the volumes:
   ```bash
   docker run --rm -v lemma_prometheus_data:/volume -v /home/ubuntu/lemma/observability-stack/backup/archive:/backup alpine sh -c "tar -xzf /backup/lemma_prometheus_data_timestamp.tar.gz -C /volume"
   docker run --rm -v lemma_loki_data:/volume -v /home/ubuntu/lemma/observability-stack/backup/archive:/backup alpine sh -c "tar -xzf /backup/lemma_loki_data_timestamp.tar.gz -C /volume"
   docker run --rm -v lemma_grafana_data:/volume -v /home/ubuntu/lemma/observability-stack/backup/archive:/backup alpine sh -c "tar -xzf /backup/lemma_grafana_data_timestamp.tar.gz -C /volume"
   docker run --rm -v lemma_tempo_data:/volume -v /home/ubuntu/lemma/observability-stack/backup/archive:/backup alpine sh -c "tar -xzf /backup/lemma_tempo_data_timestamp.tar.gz -C /volume"
   ```

4. Bring the stack up:
   ```bash
   docker compose up -d
   ```
