# Lemma Observability Stack

[![Grafana](https://img.shields.io/badge/Grafana-v11.1.0-orange?logo=grafana)](https://grafana.com)
[![Prometheus](https://img.shields.io/badge/Prometheus-v2.53.0-red?logo=prometheus)](https://prometheus.io)
[![Loki](https://img.shields.io/badge/Loki-v3.0.0-blue?logo=grafana)](https://grafana.com/oss/loki/)
[![Docker](https://img.shields.io/badge/Docker-Stack-blue?logo=docker)](https://www.docker.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue)](https://opensource.org/licenses/Apache-2.0)

This repository provides an enterprise grade, resource efficient observability stack designed for production environments. It implements full monitoring of the four golden signals (latency, traffic, errors, and saturation) and establishes log ingestion standards for containerized applications and AI services.

## Architecture

The stack is composed of the following core systems:

1. Grafana: Visualizes metrics and logs through centralized dashboards.
2. Prometheus: Collects time series metrics from hosts and containers.
3. Loki: Provides log aggregation using TSDB indexing and local filesystem storage.
4. Promtail: Processes, labels, and routes Docker and host system logs to Loki.
5. Node Exporter: Exports host level performance statistics (CPU, memory, disk, network).
6. cAdvisor: Gathers container level metrics and resource utilization details.
7. AI Application Service: A FastAPI implementation providing structured JSON log outputs for RAG and tool calls.

## Directory Structure

All configurations are modular and decoupled:

```text
observability/
  app: Simulated AI application service
  backup: Backup and restore utilities
  dashboards: Preconfigured Grafana dashboards
  grafana: Configuration and provisioning rules
  loki: Log aggregation database settings
  prometheus: Metric scraping and alert rules
  promtail: Log collection pipeline configuration
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

Build the local AI service and deploy the stack in detached mode:

```bash
docker compose up -d --build
```

### Step 3: Access Ports

1. Grafana: `http://localhost:3030` (Default credentials: admin / your password)
2. AI Service: `http://localhost:8000/docs` (Interactive API documentation)

Generate sample logs and metrics by executing a request to the chat endpoint:

```bash
curl -X POST "http://localhost:8000/api/chat" \
     -H "Content-Type: application/json" \
     -d '{"prompt": "Tell me about prometheus and system status", "model": "gpt-4o"}'
```

The system automatically provisions the custom metrics, logs, and AI performance dashboards.

### Deployment on Dokploy

This stack is production ready for Dokploy deployment using Traefik:

1. Create a Docker Compose application in your Dokploy panel.
2. Connect your Git repository.
3. Configure domains for your services using the Dokploy UI. Map your Grafana domain to the `grafana` service on container port `3000`. Map your API domain to the `ai-service` service on container port `8000`.
4. Deploy the stack. Dokploy handles the Traefik routing, TLS certificate generation, and network isolation automatically.

## Log Categorization and Ingestion

The Promtail pipeline parses logs to extract metadata for Loki:

1. JSON Parsing: Automated parsing for structured application logs to extract severity, service, and message attributes.
2. Text Fallback: Regular expressions parse unstructured text logs containing bracketed levels or key value strings.
3. Normalization: Log levels are standardized to uppercase (INFO, WARN, ERROR, DEBUG) to ensure consistent querying.
4. Source Attribution: Loki indexes container metadata, including the container name, image version, and stream.

## AI Application Observability

High cardinality metadata fields like token counts and prompt logs are kept in the log payload rather than being indexed as labels. This preserves Loki database performance. The log fields follow the OpenTelemetry GenAI Semantic Conventions. These metrics are queried via LogQL.

### LogQL Examples

To sum total tokens used:

```logql
sum(sum_over_time({container="lemma-ai-service"} | json | unwrap `gen_ai.usage.total_tokens` [$__interval]))
```

To filter logs containing tool executions:

```logql
{container="lemma-ai-service"} | json | `gen_ai.tool_calls` != "[]"
```

To isolate logs for a specific request trace:

```logql
{container="lemma-ai-service"} | json | trace_id = "target_uuid"
```

## Resource Allocation and Limits

To support deployment on small hosts, CPU and memory boundaries are set on every container:

1. Prometheus: Limited to 1200MB memory, 1.00 CPU. Retention set to 14 days or 10GB.
2. Loki: Limited to 1000MB memory, 1.00 CPU. Retention set to 7 days.
3. Grafana: Limited to 400MB memory, 0.50 CPU.
4. Promtail: Limited to 150MB memory, 0.40 CPU.
5. cAdvisor: Limited to 150MB memory, 0.40 CPU.
6. Node Exporter: Limited to 50MB memory, 0.20 CPU.
7. AI Service: Limited to 800MB memory, 1.00 CPU.

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
   ```

3. Unpack database contents back into the volumes:
   ```bash
   docker run --rm -v lemma_prometheus_data:/volume -v /home/ubuntu/lemma/observability-stack/backup/archive:/backup alpine sh -c "tar -xzf /backup/lemma_prometheus_data_timestamp.tar.gz -C /volume"
   docker run --rm -v lemma_loki_data:/volume -v /home/ubuntu/lemma/observability-stack/backup/archive:/backup alpine sh -c "tar -xzf /backup/lemma_loki_data_timestamp.tar.gz -C /volume"
   docker run --rm -v lemma_grafana_data:/volume -v /home/ubuntu/lemma/observability-stack/backup/archive:/backup alpine sh -c "tar -xzf /backup/lemma_grafana_data_timestamp.tar.gz -C /volume"
   ```

4. Bring the stack up:
   ```bash
   docker compose up -d
   ```
