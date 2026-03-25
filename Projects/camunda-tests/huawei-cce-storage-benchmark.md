# Huawei CCE Storage Class Benchmark Rehberi

Bu döküman, Huawei CCE (Cloud Container Engine) üzerindeki storage class'ların NFS gereksinimlerini karşılayıp karşılamadığını test etmek için hazırlanmıştır.

---

## Hızlı Başlangıç

```bash
# 1. Benchmark klasörüne git
cd benchmark

# 2. FIO image'ı belirle ve benchmark'ı başlat
FIO_IMAGE="swr.tr-west-1.myhuaweicloud.com/myproject/fio:3.38" ./run-benchmark.sh

# 3. Sonuçları incele
ls -la ./fio-results-*/
cat ./fio-results-*/fio-bench-efs-performance.txt

# 4. Temizlik
./cleanup.sh
```

### Dosya Yapısı

```
benchmark/
├── 01-pvcs.yaml                 # 3 PVC (efs-performance, efs-standard, nfs-rw)
├── 02-job-efs-performance.yaml  # FIO Job (6 test)
├── 03-job-efs-standard.yaml     # FIO Job (6 test)
├── 04-job-nfs-rw.yaml           # FIO Job (6 test)
├── run-benchmark.sh             # Otomasyon script
└── cleanup.sh                   # Temizlik script
```

### Test Profilleri

| # | Test | Block Size | Jobs | IODepth | Süre |
|---|------|------------|------|---------|------|
| 1 | Sequential Read | 1M | 4 | 32 | 120s |
| 2 | Sequential Write | 1M | 4 | 32 | 120s |
| 3 | Random Read 4K | 4K | 8 | 64 | 120s |
| 4 | Random Write 4K | 4K | 8 | 64 | 120s |
| 5 | Mixed R/W 70/30 | 8K | 8 | 32 | 120s |
| 6 | Latency Profile | 4K | 1 | 1 | 60s |

---

## NFS Gereksinimleri

| Gereksinim | Açıklama |
|------------|----------|
| POSIX-compliant | POSIX standartlarına uygun olmalı |
| Write ordering | Dosya işlemlerini asla yeniden sırálamamalı |
| Hard mount | Soft mount değil, hard mount olmalı |
| Single writer | Aynı anda sadece bir container yazma modunda mount edebilmeli |
| ≥1,000 IOPS | En az 1,000 IOPS sağlamalı |
| Low latency | Write/msync işlemleri düşük tek haneli milisaniye (ideal: mikrosaniye) |
| p99 <300ms | p99 latency 300 milisaniyeden düşük olmalı |

---

## Storage Tipleri Genel Bakış

```
                    Huawei CCE Storage Tipleri
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   Block Storage         File Storage          Object Storage
   (Tek Pod'a)          (Paylaşımlı)          (HTTP API)
        │                     │                     │
    ┌───┴───┐           ┌─────┴─────┐              │
    │  EVS  │           │    SFS    │            OBS
    │       │           │           │              │
  ssd/sas/sata    ┌─────┴─────┐              obs-standard
                  │           │              obs-standard-ia
             SFS Turbo    SFS Standard
                  │           │
        efs-performance    nfs-rw
        efs-standard
```

---

## 1. EVS (Elastic Volume Service) - Block Storage

| Storage Class | Tip | Açıklama |
|---------------|-----|----------|
| `ssd` | SSD | En hızlı, en pahalı |
| `sas` | SAS | Orta performans |
| `sata` | SATA | En yavaş, en ucuz |

### Neden NFS için uygun değil:

- ❌ Block storage = Sanal disk
- ❌ Sadece TEK pod'a mount edilebilir (ReadWriteOnce)
- ❌ Aynı anda birden fazla container erişemez
- ❌ NFS protokolü değil, iSCSI/FC protokolü

**Kullanım alanı:** Database (MySQL, PostgreSQL), tek pod uygulamalar

---

## 2. SFS Turbo - Yüksek Performanslı NFS

| Storage Class | Tier | Performans |
|---------------|------|------------|
| `efs-performance` | PERFORMANCE | Yüksek IOPS, düşük latency |
| `efs-standard` | STANDARD | Orta IOPS, orta latency |

### Neden NFS için uygun:

- ✅ NFS v3 protokolü
- ✅ POSIX-compliant
- ✅ ReadWriteMany (birden fazla pod aynı anda erişebilir)
- ✅ Düşük latency (sub-millisecond mümkün)
- ✅ Yüksek IOPS (10,000+)
- ✅ Hard mount destekler

### Teknik detay:

```
SFS Turbo = Huawei'nin yönetilen yüksek performanslı NFS servisi
- Dedicated storage cluster
- SSD tabanlı backend
- Parallel file system mimarisi
```

---

## 3. SFS Standard - Standart NFS

| Storage Class | Tip |
|---------------|-----|
| `nfs-rw` | Standard NFS |

### Durumu:

- ⚠️ NFS protokolü = Uygun
- ⚠️ POSIX-compliant = Uygun
- ⚠️ ReadWriteMany = Uygun
- ❓ Performans = Sınırda (test gerekli)

### Neden "sınırda":

- SFS Turbo'ya göre daha yavaş
- Shared infrastructure (noisy neighbor problemi)
- Latency genellikle 5-15ms arası
- IOPS sınırlı (~1000-2000)

---

## 4. OBS (Object Storage Service)

| Storage Class | Tier | Açıklama |
|---------------|------|----------|
| `obs-standard` | Standard | Sık erişim |
| `obs-standard-ia` | Infrequent Access | Nadir erişim, ucuz |

### Neden NFS için uygun DEĞİL:

- ❌ Object storage = HTTP/S3 API ile erişim
- ❌ POSIX-compliant DEĞİL
- ❌ Dosya sistemi semantiği yok
- ❌ Write ordering garanti edilmez
- ❌ Latency çok yüksek (100ms+)
- ❌ Random I/O için uygun değil

**Kullanım alanı:** Backup, statik dosyalar, log arşivi, medya dosyaları

---

## 5. Local PV - Yerel Disk

| Storage Class | Binding |
|---------------|---------|
| `csi-local` | Immediate |
| `csi-local-topology` | WaitForFirstConsumer |

### Neden NFS için uygun DEĞİL:

- ❌ Node'un yerel diski
- ❌ Paylaşılamaz (sadece o node'daki pod'lar erişir)
- ❌ Pod başka node'a taşınırsa veri kaybolur
- ❌ NFS protokolü değil

**Kullanım alanı:** Cache, geçici veri, yüksek performans gereken tek-node uygulamalar

---

## Özet Karşılaştırma Tablosu

| Storage Class | Protokol | Multi-Pod | POSIX | Write Order | IOPS | Latency | NFS Uyumu |
|---------------|----------|-----------|-------|-------------|------|---------|-----------|
| `efs-performance` | NFS v3 | ✅ | ✅ | ✅ | 10K+ | <2ms | ✅ |
| `efs-standard` | NFS v3 | ✅ | ✅ | ✅ | 5K+ | 2-5ms | ✅ |
| `nfs-rw` | NFS v3/v4 | ✅ | ✅ | ✅ | ~1K | 5-15ms | ⚠️ |
| `ssd` | iSCSI | ❌ | ✅ | ✅ | 20K+ | <1ms | ❌ |
| `sas` | iSCSI | ❌ | ✅ | ✅ | 5K+ | 1-2ms | ❌ |
| `sata` | iSCSI | ❌ | ✅ | ✅ | 1K+ | 5ms | ❌ |
| `obs-standard` | HTTP/S3 | ✅ | ❌ | ❌ | N/A | 100ms+ | ❌ |
| `csi-local` | Local | ❌ | ✅ | ✅ | 50K+ | <0.5ms | ❌ |

---

## Gereksinimlerle Eşleştirme

| Gereksinim | efs-performance | efs-standard | nfs-rw |
|------------|-----------------|--------------|--------|
| POSIX-compliant | ✅ | ✅ | ✅ |
| Never reorder file operations | ✅ | ✅ | ✅ |
| Hard mount support | ✅ | ✅ | ✅ |
| Single writer (configurable) | ✅ | ✅ | ✅ |
| ≥1,000 IOPS | ✅ | ✅ | ⚠️ |
| Low single-digit ms latency | ✅ | ✅ | ❌ |
| p99 latency <300ms | ✅ | ✅ | ⚠️ |
| **SONUÇ** | **UYGUN** | **UYGUN** | **TEST ET** |

**Öneri sırası:** `efs-performance` > `efs-standard` > `nfs-rw`

---

## FIO Benchmark Testleri

### Test PVC'leri

```yaml
# efs-performance-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fio-test-efs-performance
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-performance
  resources:
    requests:
      storage: 10Gi
---
# efs-standard-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fio-test-efs-standard
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-standard
  resources:
    requests:
      storage: 10Gi
---
# nfs-rw-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fio-test-nfs-rw
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-rw
  resources:
    requests:
      storage: 10Gi
```

### Test Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fio-storage-test
spec:
  containers:
  - name: fio
    image: nixery.dev/shell/fio
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: efs-perf
      mountPath: /mnt/efs-performance
    - name: efs-std
      mountPath: /mnt/efs-standard
    - name: nfs
      mountPath: /mnt/nfs-rw
  volumes:
  - name: efs-perf
    persistentVolumeClaim:
      claimName: fio-test-efs-performance
  - name: efs-std
    persistentVolumeClaim:
      claimName: fio-test-efs-standard
  - name: nfs
    persistentVolumeClaim:
      claimName: fio-test-nfs-rw
```

### FIO Test Komutları

#### 1. IOPS Testi (≥1,000 IOPS)

```bash
fio --name=iops-test \
    --directory=/mnt/nfs \
    --ioengine=libaio \
    --direct=1 \
    --rw=randwrite \
    --bs=4k \
    --numjobs=4 \
    --iodepth=32 \
    --size=1G \
    --runtime=60 \
    --time_based \
    --group_reporting
```

#### 2. Write Latency Testi

```bash
fio --name=latency-test \
    --directory=/mnt/nfs \
    --ioengine=sync \
    --rw=write \
    --bs=4k \
    --numjobs=1 \
    --iodepth=1 \
    --size=512M \
    --runtime=60 \
    --time_based \
    --fsync=1 \
    --group_reporting \
    --lat_percentiles=1
```

#### 3. p99 Latency Testi (<300ms)

```bash
fio --name=p99-latency-test \
    --directory=/mnt/nfs \
    --ioengine=sync \
    --rw=randwrite \
    --bs=4k \
    --numjobs=1 \
    --iodepth=1 \
    --size=1G \
    --runtime=120 \
    --time_based \
    --fsync=1 \
    --percentile_list=50:90:95:99:99.9 \
    --group_reporting
```

### Otomatik Test Script'i

```bash
#!/bin/bash

STORAGES=("efs-performance" "efs-standard" "nfs-rw")
RESULTS_DIR="/tmp/fio-results"
mkdir -p $RESULTS_DIR

for storage in "${STORAGES[@]}"; do
    echo "=========================================="
    echo "Testing: $storage"
    echo "=========================================="

    DIR="/mnt/$storage"

    # 1. IOPS Testi
    echo "[IOPS Test]"
    fio --name=iops-$storage \
        --directory=$DIR \
        --ioengine=libaio \
        --direct=1 \
        --rw=randwrite \
        --bs=4k \
        --numjobs=4 \
        --iodepth=32 \
        --size=1G \
        --runtime=60 \
        --time_based \
        --group_reporting \
        --output=$RESULTS_DIR/${storage}-iops.json \
        --output-format=json

    # 2. Latency Testi (fsync ile)
    echo "[Latency Test]"
    fio --name=latency-$storage \
        --directory=$DIR \
        --ioengine=sync \
        --rw=write \
        --bs=4k \
        --numjobs=1 \
        --iodepth=1 \
        --size=512M \
        --runtime=60 \
        --time_based \
        --fsync=1 \
        --percentile_list=50:90:95:99:99.9 \
        --group_reporting \
        --output=$RESULTS_DIR/${storage}-latency.json \
        --output-format=json

    echo ""
done

echo "Results saved to $RESULTS_DIR"
```

---

## FIO Parametreleri Açıklaması

| Parametre | Değer | Neden |
|-----------|-------|-------|
| `--bs=4k` | 4KB | Tipik container/database I/O boyutu |
| `--ioengine=libaio` | Async I/O | IOPS testinde maksimum throughput için |
| `--ioengine=sync` | Sync I/O | Latency testinde gerçek latency ölçümü için |
| `--iodepth=32` | Queue depth 32 | IOPS testinde storage'ı doyurmak için |
| `--iodepth=1` | Queue depth 1 | Latency testinde izole ölçüm için |
| `--direct=1` | OS cache bypass | Gerçek disk performansı ölçümü |
| `--fsync=1` | Her write sonrası fsync | Write ordering testi için kritik |
| `--numjobs=4` | 4 paralel iş | Tipik container workload paralelliği |
| `--runtime=60` | 60 saniye | Stabilize sonuç almak için yeterli süre |

---

## Sonuçları Değerlendirme

| Metrik | Gereksinim | fio Çıktısında Bakılacak Yer |
|--------|-----------|------------------------------|
| IOPS | ≥1,000 | `write: IOPS=XXX` |
| Write Latency | <10ms (ideal <1ms) | `lat (usec/msec): avg=XXX` |
| p99 Latency | <300ms | `clat percentiles: 99.00th=[XXX]` |

---

## Beklenen Sonuçlar

| Storage Class | Beklenen IOPS | Beklenen Latency | Uygun mu? |
|---------------|---------------|------------------|-----------|
| `efs-performance` | 10,000+ | <2ms | ✅ Muhtemelen |
| `efs-standard` | 3,000-5,000 | 2-5ms | ✅ Muhtemelen |
| `nfs-rw` | 1,000-2,000 | 5-15ms | ⚠️ Sınırda |

---

## Production-Grade Otomasyon Suite

### Dosya Yapısı

```
camunda-tests/
├── huawei-cce-storage-benchmark.md  (bu dosya)
└── benchmark/
    ├── 01-pvcs.yaml                 # 3 PVC tanımı
    ├── 02-job-efs-performance.yaml  # FIO Job (6 test)
    ├── 03-job-efs-standard.yaml     # FIO Job (6 test)
    ├── 04-job-nfs-rw.yaml           # FIO Job (6 test)
    ├── run-benchmark.sh             # Otomasyon script
    └── cleanup.sh                   # Temizlik script
```

### Test Profilleri

Her storage class için 6 test çalıştırılır:

| Test | Block Size | Jobs | IODepth | Süre | Amaç |
|------|------------|------|---------|------|------|
| Sequential Read | 1M | 4 | 32 | 120s | Throughput ölçümü |
| Sequential Write | 1M | 4 | 32 | 120s | Throughput ölçümü |
| Random Read 4K | 4K | 8 | 64 | 120s | IOPS ölçümü |
| Random Write 4K | 4K | 8 | 64 | 120s | IOPS ölçümü |
| Mixed R/W 70/30 | 8K | 8 | 32 | 120s | Gerçekçi workload |
| Latency Profile | 4K | 1 | 1 | 60s | Latency percentiles |

### Kullanım

#### 1. Ön Gereksinimler

- Kubernetes cluster'a erişim (kubectl yapılandırılmış)
- Huawei Registry'den FIO image erişimi
- Storage class'ların mevcut olması (`efs-performance`, `efs-standard`, `nfs-rw`)

#### 2. Benchmark Çalıştırma

```bash
cd benchmark

# FIO image'ı environment variable olarak belirt
export FIO_IMAGE="swr.tr-west-1.myhuaweicloud.com/myproject/fio:3.38"

# Benchmark'ı başlat
./run-benchmark.sh
```

Veya tek satırda:

```bash
FIO_IMAGE="swr.tr-west-1.myhuaweicloud.com/myproject/fio:3.38" ./run-benchmark.sh
```

#### 3. Sonuçları İnceleme

Sonuçlar `./fio-results-YYYYMMDD-HHMMSS/` klasöründe saklanır:

```bash
ls -la ./fio-results-*/
cat ./fio-results-*/fio-bench-efs-performance.txt
```

#### 4. Temizlik

```bash
./cleanup.sh
```

### YAML Syntax Doğrulama

```bash
# Dry-run ile test et
kubectl apply --dry-run=client -f benchmark/01-pvcs.yaml
```

### Manuel Çalıştırma (İsteğe Bağlı)

Otomasyon scripti yerine manuel çalıştırmak için:

```bash
# 1. Namespace oluştur
kubectl create ns fio-benchmark

# 2. PVC'leri oluştur (envsubst gereksiz - PVC'de image yok)
kubectl apply -f benchmark/01-pvcs.yaml

# 3. PVC'lerin Bound olmasını bekle
kubectl get pvc -n fio-benchmark -w

# 4. Job'ları sırayla çalıştır (FIO_IMAGE değiştir)
export FIO_IMAGE="swr.../fio:3.38"
envsubst < benchmark/02-job-efs-performance.yaml | kubectl apply -f -

# 5. Logları izle
kubectl logs -f job/fio-bench-efs-performance -n fio-benchmark
```

### Sorun Giderme

| Sorun | Çözüm |
|-------|-------|
| PVC Pending kalıyor | `kubectl describe pvc -n fio-benchmark` ile storage class'ı kontrol et |
| Pod ImagePullBackOff | FIO_IMAGE yolunu ve registry erişimini kontrol et |
| Job timeout | `kubectl describe job -n fio-benchmark` ile olayları incele |
| Permission denied | PVC mount izinlerini ve securityContext'i kontrol et |
