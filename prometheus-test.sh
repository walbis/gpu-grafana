#!/bin/bash
#
# Dashboard v6 Prometheus Test Script
# Canlı ortamda metrik varlığını ve doğruluğunu kontrol eder
#
# Kullanım: ./prometheus-test.sh [PROMETHEUS_URL]
# Örnek:    ./prometheus-test.sh http://localhost:9090
#

PROMETHEUS_URL="${1:-http://prometheus:9090}"

echo "=========================================="
echo "Dashboard v6 Prometheus Test"
echo "=========================================="
echo "Prometheus URL: $PROMETHEUS_URL"
echo ""

# Function to query Prometheus
query_prom() {
    local query="$1"
    local result=$(curl -s -G --data-urlencode "query=$query" "$PROMETHEUS_URL/api/v1/query" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null)
    echo "${result:-0}"
}

query_prom_value() {
    local query="$1"
    curl -s -G --data-urlencode "query=$query" "$PROMETHEUS_URL/api/v1/query" 2>/dev/null | jq -r '.data.result[0].value[1] // "N/A"' 2>/dev/null
}

echo "=========================================="
echo "TEST 4.1: TEMEL METRİK VARLIK KONTROLÜ"
echo "=========================================="

metrics=(
    "DCGM_FI_DEV_GPU_TEMP"
    "DCGM_FI_DEV_FB_USED"
    "DCGM_FI_DEV_FB_FREE"
    "DCGM_FI_DEV_FB_TOTAL"
    "DCGM_FI_DEV_POWER_USAGE"
    "DCGM_FI_DEV_XID_ERRORS"
    "DCGM_FI_DEV_ECC_DBE_VOL_TOTAL"
)

for metric in "${metrics[@]}"; do
    count=$(query_prom "count($metric)")
    if [ "$count" -gt 0 ]; then
        echo "✓ $metric: $count series"
    else
        echo "✗ $metric: NOT FOUND"
    fi
done

echo ""
echo "=========================================="
echo "TEST 4.2: PROFİLİNG METRİK KONTROLÜ"
echo "=========================================="

profiling_metrics=(
    "DCGM_FI_PROF_GR_ENGINE_ACTIVE"
    "DCGM_FI_PROF_SM_ACTIVE"
    "DCGM_FI_PROF_SM_OCCUPANCY"
)

for metric in "${profiling_metrics[@]}"; do
    count=$(query_prom "count($metric)")
    if [ "$count" -gt 0 ]; then
        echo "✓ $metric: $count series"
    else
        echo "⚠ $metric: NOT FOUND (profiling collector gerektirir)"
    fi
done

echo ""
echo "=========================================="
echo "TEST 10.1: FİZİKSEL GPU SAYISI DOĞRULAMA"
echo "=========================================="

physical_new=$(query_prom_value 'count(count by (UUID) (DCGM_FI_DEV_GPU_TEMP))')
physical_old=$(query_prom_value 'count(count by (UUID, GPU_I_ID) (DCGM_FI_DEV_GPU_TEMP))')

echo "Yeni sorgu (sadece UUID): $physical_new"
echo "Eski sorgu (UUID + GPU_I_ID): $physical_old"
if [ "$physical_new" != "N/A" ] && [ "$physical_old" != "N/A" ]; then
    if [ "${physical_new%.*}" -lt "${physical_old%.*}" ] 2>/dev/null; then
        echo "✓ MIG aktif: Fiziksel GPU < Toplam instance"
    elif [ "${physical_new%.*}" -eq "${physical_old%.*}" ] 2>/dev/null; then
        echo "✓ MIG pasif veya yok: Fiziksel GPU = Toplam instance"
    else
        echo "⚠ Beklenmeyen durum"
    fi
fi

echo ""
echo "=========================================="
echo "TEST 10.2: MIG INSTANCE SAYISI"
echo "=========================================="

mig_count=$(query_prom_value 'count(count by (UUID, GPU_I_ID) (DCGM_FI_DEV_GPU_TEMP{GPU_I_ID!=""}))')
echo "MIG Instance sayısı: $mig_count"

echo ""
echo "GPU_I_ID label değerleri:"
curl -s -G --data-urlencode 'query=count by (GPU_I_ID) (DCGM_FI_DEV_GPU_TEMP)' "$PROMETHEUS_URL/api/v1/query" 2>/dev/null | \
    jq -r '.data.result[] | "  - GPU_I_ID=\"\(.metric.GPU_I_ID)\": \(.value[1]) series"' 2>/dev/null

echo ""
echo "=========================================="
echo "TEST 10.3: SM METRİKLERİ DEĞER KONTROLÜ"
echo "=========================================="

sm_active=$(query_prom_value 'avg(DCGM_FI_PROF_SM_ACTIVE)')
sm_occupancy=$(query_prom_value 'avg(DCGM_FI_PROF_SM_OCCUPANCY)')

echo "SM Active ortalama: $sm_active"
echo "SM Occupancy ortalama: $sm_occupancy"

if [ "$sm_active" != "N/A" ]; then
    # Check if value is between 0 and 1
    in_range=$(echo "$sm_active" | awk '{if ($1 >= 0 && $1 <= 1) print "✓"; else print "✗"}')
    echo "$in_range SM Active değer aralığı (0-1)"
fi

if [ "$sm_occupancy" != "N/A" ]; then
    in_range=$(echo "$sm_occupancy" | awk '{if ($1 >= 0 && $1 <= 1) print "✓"; else print "✗"}')
    echo "$in_range SM Occupancy değer aralığı (0-1)"
fi

echo ""
echo "=========================================="
echo "TEST 10.4: label_join KONTROLÜ"
echo "=========================================="

echo "gpu_key format test:"
curl -s -G --data-urlencode 'query=label_join(max by (UUID, GPU_I_ID) (DCGM_FI_DEV_GPU_TEMP), "gpu_key", ":", "UUID", "GPU_I_ID")' "$PROMETHEUS_URL/api/v1/query" 2>/dev/null | \
    jq -r '.data.result[:3][] | "  - gpu_key=\"\(.metric.gpu_key)\""' 2>/dev/null

echo ""
echo "=========================================="
echo "TEST 10.5: BELLEK METRİKLERİ TUTARLILIK"
echo "=========================================="

fb_total_count=$(query_prom 'count(DCGM_FI_DEV_FB_TOTAL)')
echo "FB_TOTAL metrik sayısı: $fb_total_count"

if [ "$fb_total_count" -gt 0 ]; then
    diff=$(query_prom_value 'max(abs(max by (UUID, GPU_I_ID) (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) - max by (UUID, GPU_I_ID) (DCGM_FI_DEV_FB_TOTAL)))')
    echo "FB_USED + FB_FREE - FB_TOTAL farkı: $diff"
    if [ "$diff" != "N/A" ]; then
        is_ok=$(echo "$diff" | awk '{if ($1 < 10) print "✓"; else print "✗"}')
        echo "$is_ok Bellek metrikleri tutarlı (fark < 10 MiB)"
    fi
else
    echo "⚠ FB_TOTAL metriği yok, fallback hesaplama kullanılacak"
fi

echo ""
echo "=========================================="
echo "TEST TAMAMLANDI"
echo "=========================================="
