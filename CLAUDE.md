# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a Grafana dashboard configuration for NVIDIA GPU monitoring in Kubernetes/OpenShift environments. The dashboard visualizes metrics collected by NVIDIA DCGM (Data Center GPU Manager) Exporter via Prometheus.

## Architecture

```
NVIDIA GPUs (K8s Cluster) → DCGM Exporter → Prometheus → Grafana Dashboard
```

The dashboard (`dashboard.txt`) is a complete Grafana JSON configuration that can be imported directly into any Grafana instance with a Prometheus datasource.

## Dashboard Sections

- **Summary Row**: Total GPU count, active GPUs, utilization/memory gauges, temperature, power, errors
- **Trend Charts**: Utilization, memory, temperature, and power trends over time
- **Pod Details**: Per-pod GPU utilization and memory usage
- **GPU Detail Table**: Complete listing with model, node, MIG profile, metrics
- **Per-GPU Panels**: Individual GPU monitoring charts

## Key Metrics (DCGM_FI_*)

- `DCGM_FI_DEV_GPU_UTIL` - GPU utilization percentage
- `DCGM_FI_DEV_FB_USED` / `DCGM_FI_DEV_FB_FREE` - Memory usage
- `DCGM_FI_DEV_GPU_TEMP` - Temperature (Celsius)
- `DCGM_FI_DEV_POWER_USAGE` - Power consumption (watts)
- `DCGM_FI_DEV_XID_ERRORS` - XID error count
- `DCGM_FI_DEV_ECC_DBE_VOL` - ECC double-bit errors

## Threshold Values

- **Utilization**: Green <70%, Yellow 70-90%, Red >90%
- **Temperature**: Green <75°C, Yellow 75°C, Orange 83°C, Red >90°C

## Deployment

1. Ensure DCGM Exporter is deployed to Kubernetes cluster
2. Configure Prometheus to scrape DCGM metrics
3. Import `dashboard.txt` into Grafana (Dashboard → Import → Upload JSON)
4. Select the Prometheus datasource
5. Use hostname/GPU UUID filters to focus on specific nodes
