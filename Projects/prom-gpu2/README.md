# GPU Timeline Dashboard

OpenShift uzerinde NVIDIA GPU kullanim takibi icin Gantt chart benzeri timeline dashboard.

## Ozellikler

- **Gantt Chart Timeline**: Her GPU icin zaman bazli kullanim gosterimi
- **MIG Destegi**: MIG slice'lar nested (alt satir) olarak gosterilir
- **Renk Kodlamasi**: Utilization seviyesine gore otomatik renklendirme
- **Interaktif Tooltip**: Pod ismi, utilization, memory ve zaman bilgisi
- **5 Dakikalik Periyotlar**: Prometheus recording rules ile optimize edilmis
- **7 Gunluk Retention**: Son 7 gune kadar gecmis analizi

## Kurulum

### 1. Apache ECharts Plugin

```bash
# Grafana CLI ile
grafana-cli plugins install volkovlabs-echarts-panel

# Kubernetes/OpenShift
kubectl exec -it <grafana-pod> -- grafana-cli plugins install volkovlabs-echarts-panel
kubectl rollout restart deployment grafana -n <namespace>
```

### 2. Prometheus Recording Rules

Recording rules dosyasini Prometheus'a ekleyin:

```bash
# Standalone Prometheus
cp prometheus-rules.yaml /etc/prometheus/rules/gpu-timeline-rules.yaml
# prometheus.yml'e ekleyin:
# rule_files:
#   - /etc/prometheus/rules/gpu-timeline-rules.yaml

# OpenShift
oc apply -f prometheus-rules.yaml -n openshift-monitoring
```

**Not:** OpenShift icin `prometheus-rules.yaml` dosyasini PrometheusRule CR formatina donusturmeniz gerekebilir.

### 3. Dashboard Import

1. Grafana > Dashboards > Import
2. `dashboard-gantt.json` dosyasini yukleyin
3. Datasource olarak merkezi Prometheus'u secin
4. Import'a tiklayin

## Dosya Yapisi

```
prom-gpu2/
├── prometheus-rules.yaml   # Prometheus recording rules
├── dashboard-gantt.json    # Grafana dashboard JSON
├── echarts-config.js       # ECharts panel kodu (referans)
└── README.md               # Bu dosya
```

## Recording Rules

| Rule | Aciklama |
|------|----------|
| `gpu:utilization:avg5m` | 5dk ortalama GPU utilization (0-100) |
| `gpu:memory_used_mib:avg5m` | 5dk ortalama memory kullanimi (MiB) |
| `gpu:memory_percent:avg5m` | 5dk ortalama memory yuzde (0-100) |
| `gpu:pod_active:info` | Aktif pod-GPU eslesmesi |
| `gpu:mig_slices:info` | MIG slice bilgileri |

## Renk Kodlamasi

| Renk | Utilization | Aciklama |
|------|-------------|----------|
| Gri | Idle | Pod yok veya < 1% |
| Yesil | 0-30% | Dusuk kullanim |
| Sari | 30-70% | Orta kullanim |
| Turuncu | 70-90% | Yuksek kullanim |
| Kirmizi | 90-100% | Kritik kullanim |

## Dashboard Panelleri

1. **GPU Timeline (Gantt)**: Ana timeline gorunumu
2. **Heatmap**: Kompakt utilization matrisi
3. **Stacked Area**: Toplam kapasite kullanimi
4. **Detay Tablosu**: Anlik GPU metrikleri

## Kullanim

### Filtreler

- **Hostname**: Node bazli filtreleme (coklu secim destekler)
- **Time Range**: Varsayilan 7 gun, degistirilebilir

### Interaksiyon

- **Zoom**: Mouse scroll veya alt slider ile
- **Tooltip**: Bar uzerine gelince detaylar
- **Pan**: Grafik uzerinde surukle-birak

## Gereksinimler

- Grafana 10.x+
- Prometheus (15+ gun retention onerilen)
- DCGM Exporter (DCGM 4.2.3+)
- Apache ECharts plugin (volkovlabs-echarts-panel)

## Sorun Giderme

### Recording rules calismiyorsa

```bash
# Prometheus'ta kontrol
curl -s "http://prometheus:9090/api/v1/query?query=gpu:utilization:avg5m" | jq '.data.result | length'
# Sonuc 0 ise rules yuklenmemis
```

### ECharts paneli bossa

1. Browser console'da hata kontrol edin
2. Prometheus query'lerinin veri dondurdugunu dogrulayin
3. Time range'i daraltip deneyin (son 1 saat)

### MIG slice'lar gozukmuyorsa

DCGM exporter'da MIG destegi aktif olmali:
```bash
# DCGM metriklerinde GPU_I_ID label'i olmali
curl -s localhost:9400/metrics | grep GPU_I_ID
```

## Lisans

MIT
