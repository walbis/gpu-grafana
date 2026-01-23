/**
 * GPU Timeline Gantt Chart - ECharts Configuration
 * ================================================
 * Bu dosya Grafana ECharts panel icinde kullanilacak konfigurasyonu icerir.
 *
 * Kullanim:
 * 1. Grafana'da ECharts paneli olusturun
 * 2. Panel Options > Function sekmesine gidin
 * 3. Asagidaki kodu yapistirin
 *
 * Prometheus Query'leri (A, B, C refId'leri ile):
 * A: gpu:utilization:avg5m{Hostname=~"$hostname"}
 * B: gpu:memory_percent:avg5m{Hostname=~"$hostname"}
 * C: gpu:pod_active:info{Hostname=~"$hostname"}
 */

// ============================================
// GRAFANA ECHARTS PANEL KODU - BASLANGIC
// ============================================

// Veri serilerini al
const utilizationData = data.series.find(s => s.refId === 'A');
const memoryData = data.series.find(s => s.refId === 'B');
const podData = data.series.find(s => s.refId === 'C');

// Veri yoksa bekleme mesaji goster
if (!utilizationData || !utilizationData.fields) {
  return {
    title: {
      text: 'Veri bekleniyor...',
      left: 'center',
      top: 'center',
      textStyle: { color: '#999', fontSize: 16 }
    },
    series: []
  };
}

// ============================================
// RENK TANIMLARI
// ============================================
const COLORS = {
  idle: '#808080',      // Gri - Idle
  low: '#73BF69',       // Yesil - 0-30%
  medium: '#FADE2A',    // Sari - 30-70%
  high: '#FF9830',      // Turuncu - 70-90%
  critical: '#F2495C'   // Kirmizi - 90-100%
};

const getColor = (util) => {
  if (util < 1) return COLORS.idle;
  if (util < 30) return COLORS.low;
  if (util < 70) return COLORS.medium;
  if (util < 90) return COLORS.high;
  return COLORS.critical;
};

const getColorName = (util) => {
  if (util < 1) return 'Idle';
  if (util < 30) return 'Dusuk';
  if (util < 70) return 'Orta';
  if (util < 90) return 'Yuksek';
  return 'Kritik';
};

// ============================================
// GPU VE MIG MAPPING
// ============================================
const gpuMap = new Map();
const migMap = new Map();

utilizationData.fields.forEach(field => {
  if (field.name === 'Time') return;

  const labels = field.labels || {};
  const hostname = labels.Hostname || 'unknown';
  const uuid = labels.UUID || field.name;
  const gpuId = labels.gpu || '0';
  const migId = labels.GPU_I_ID || '';
  const migProfile = labels.GPU_I_PROFILE || '';
  const modelName = labels.modelName || 'GPU';
  const exportedPod = labels.exported_pod || '';

  const gpuKey = `${hostname}|${uuid}`;

  if (migId && migId !== '') {
    // MIG slice
    if (!migMap.has(gpuKey)) {
      migMap.set(gpuKey, []);
    }
    migMap.get(gpuKey).push({
      migId,
      migProfile,
      field,
      labels,
      exportedPod
    });
  } else {
    // Normal GPU
    gpuMap.set(gpuKey, {
      hostname,
      uuid,
      gpuId,
      modelName,
      field,
      labels,
      exportedPod
    });
  }
});

// ============================================
// Y-AXIS KATEGORILERI (GPU Listesi)
// ============================================
const yAxisData = [];
const gpuDataMap = new Map();
let yIndex = 0;

// Hostname'e gore sirala
const sortedGpuKeys = Array.from(gpuMap.keys()).sort((a, b) => {
  const hostA = a.split('|')[0];
  const hostB = b.split('|')[0];
  return hostA.localeCompare(hostB);
});

sortedGpuKeys.forEach(key => {
  const gpu = gpuMap.get(key);
  const displayName = `${gpu.hostname} / GPU-${gpu.gpuId} [${gpu.modelName}]`;
  yAxisData.push(displayName);
  gpuDataMap.set(key, { yIndex, ...gpu, displayName });
  yIndex++;

  // MIG slice'lari ekle (nested gorunum)
  const migs = migMap.get(key) || [];
  migs.sort((a, b) => parseInt(a.migId) - parseInt(b.migId));
  migs.forEach(mig => {
    const migDisplayName = `  └─ MIG ${mig.migProfile} (${mig.migId})`;
    yAxisData.push(migDisplayName);
    gpuDataMap.set(`${key}|MIG|${mig.migId}`, {
      yIndex,
      ...mig,
      displayName: migDisplayName,
      parentKey: key
    });
    yIndex++;
  });
});

// ============================================
// ZAMAN VERISI
// ============================================
const timeField = utilizationData.fields.find(f => f.name === 'Time');
const times = timeField ? timeField.values : [];

// ============================================
// GANTT BAR VERISI OLUSTUR
// ============================================
const seriesData = [];

gpuDataMap.forEach((gpuInfo, key) => {
  const field = gpuInfo.field;
  if (!field || !field.values) return;

  const values = field.values;
  const labels = gpuInfo.labels || {};

  // Ardisik ayni utilization seviyelerini birlestir
  let segmentStart = 0;
  let segmentUtil = values[0] * 100;

  for (let i = 1; i <= values.length; i++) {
    const currentUtil = i < values.length ? values[i] * 100 : -1;
    const prevUtil = values[i-1] * 100;

    // Seviye degisikligi kontrolu (30% araliklar)
    const prevLevel = Math.floor(prevUtil / 20);
    const currLevel = Math.floor(currentUtil / 20);

    const shouldSplit = (
      i === values.length ||
      prevLevel !== currLevel ||
      Math.abs(currentUtil - segmentUtil) > 15
    );

    if (shouldSplit && segmentStart < i) {
      const startTime = times[segmentStart];
      const endTime = times[i-1] || times[times.length - 1];

      // Segment icindeki ortalama utilization
      let sumUtil = 0;
      for (let j = segmentStart; j < i; j++) {
        sumUtil += values[j] * 100;
      }
      const avgUtil = sumUtil / (i - segmentStart);

      seriesData.push({
        value: [
          gpuInfo.yIndex,
          startTime,
          endTime,
          avgUtil
        ],
        itemStyle: {
          color: getColor(avgUtil),
          borderColor: 'rgba(255,255,255,0.3)',
          borderWidth: 1
        },
        labels: labels,
        hostname: gpuInfo.hostname || labels.Hostname,
        gpuId: gpuInfo.gpuId || labels.gpu,
        modelName: gpuInfo.modelName || labels.modelName,
        exportedPod: labels.exported_pod || 'N/A',
        displayName: gpuInfo.displayName
      });

      segmentStart = i;
      segmentUtil = currentUtil;
    }
  }
});

// ============================================
// ECHARTS OPTION
// ============================================
return {
  backgroundColor: 'transparent',

  // Tooltip konfigurasyonu
  tooltip: {
    trigger: 'item',
    backgroundColor: 'rgba(30, 30, 30, 0.95)',
    borderColor: '#444',
    borderWidth: 1,
    textStyle: {
      color: '#fff',
      fontSize: 12
    },
    formatter: function(params) {
      const d = params.data;
      if (!d || !d.value) return '';

      const startTime = new Date(d.value[1]).toLocaleString('tr-TR');
      const endTime = new Date(d.value[2]).toLocaleString('tr-TR');
      const util = d.value[3].toFixed(1);
      const duration = Math.round((d.value[2] - d.value[1]) / 60000); // dakika

      return `
        <div style="padding: 8px; min-width: 200px;">
          <div style="font-weight: bold; font-size: 13px; margin-bottom: 8px; border-bottom: 1px solid #444; padding-bottom: 4px;">
            ${d.displayName || yAxisData[d.value[0]]}
          </div>
          <table style="width: 100%;">
            <tr><td style="color: #aaa;">Pod:</td><td style="text-align: right; font-weight: bold;">${d.exportedPod}</td></tr>
            <tr><td style="color: #aaa;">Utilization:</td><td style="text-align: right;"><span style="color: ${getColor(parseFloat(util))}; font-weight: bold;">${util}%</span> (${getColorName(parseFloat(util))})</td></tr>
            <tr><td style="color: #aaa;">Sure:</td><td style="text-align: right;">${duration} dakika</td></tr>
            <tr><td style="color: #aaa;">Baslangic:</td><td style="text-align: right; font-size: 11px;">${startTime}</td></tr>
            <tr><td style="color: #aaa;">Bitis:</td><td style="text-align: right; font-size: 11px;">${endTime}</td></tr>
          </table>
        </div>
      `;
    }
  },

  // Legend
  legend: {
    show: true,
    data: [
      { name: 'Idle', itemStyle: { color: COLORS.idle } },
      { name: 'Dusuk (0-30%)', itemStyle: { color: COLORS.low } },
      { name: 'Orta (30-70%)', itemStyle: { color: COLORS.medium } },
      { name: 'Yuksek (70-90%)', itemStyle: { color: COLORS.high } },
      { name: 'Kritik (90-100%)', itemStyle: { color: COLORS.critical } }
    ],
    bottom: 5,
    itemWidth: 18,
    itemHeight: 12,
    textStyle: { color: '#ccc', fontSize: 11 }
  },

  // Grid
  grid: {
    left: '18%',
    right: '3%',
    top: '3%',
    bottom: '18%',
    containLabel: false
  },

  // X-Axis (Zaman)
  xAxis: {
    type: 'time',
    axisLine: { lineStyle: { color: '#444' } },
    axisLabel: {
      color: '#aaa',
      fontSize: 10,
      formatter: function(value) {
        const date = new Date(value);
        const day = date.toLocaleDateString('tr-TR', { day: '2-digit', month: '2-digit' });
        const time = date.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
        return `${day}\n${time}`;
      }
    },
    splitLine: {
      show: true,
      lineStyle: { color: '#333', type: 'dashed' }
    }
  },

  // Y-Axis (GPU Listesi)
  yAxis: {
    type: 'category',
    data: yAxisData,
    axisLine: { lineStyle: { color: '#444' } },
    axisLabel: {
      color: '#ccc',
      fontSize: 11,
      width: 200,
      overflow: 'truncate',
      formatter: function(value) {
        // MIG satirlari icin indent
        if (value.startsWith('  └─')) {
          return value;
        }
        // Uzun isimleri kisalt
        if (value.length > 35) {
          return value.substring(0, 32) + '...';
        }
        return value;
      }
    },
    inverse: true,
    splitLine: {
      show: true,
      lineStyle: { color: '#222' }
    }
  },

  // DataZoom (Zoom kontrolleri)
  dataZoom: [
    {
      type: 'slider',
      xAxisIndex: 0,
      filterMode: 'none',
      bottom: 30,
      height: 20,
      borderColor: '#444',
      backgroundColor: '#1a1a1a',
      fillerColor: 'rgba(100, 100, 100, 0.3)',
      handleStyle: { color: '#666' },
      textStyle: { color: '#aaa' }
    },
    {
      type: 'inside',
      xAxisIndex: 0,
      filterMode: 'none',
      zoomOnMouseWheel: true,
      moveOnMouseMove: true
    },
    {
      type: 'slider',
      yAxisIndex: 0,
      filterMode: 'none',
      right: 5,
      width: 15,
      borderColor: '#444',
      backgroundColor: '#1a1a1a',
      fillerColor: 'rgba(100, 100, 100, 0.3)'
    }
  ],

  // Series (Gantt Barlari)
  series: [
    {
      name: 'GPU Timeline',
      type: 'custom',
      renderItem: function(params, api) {
        const yValue = api.value(0);
        const startTime = api.coord([api.value(1), yValue]);
        const endTime = api.coord([api.value(2), yValue]);
        const height = api.size([0, 1])[1] * 0.65;

        const rectShape = {
          x: startTime[0],
          y: startTime[1] - height / 2,
          width: Math.max(endTime[0] - startTime[0], 3),
          height: height,
          r: 2 // Kose yuvarlatma
        };

        return {
          type: 'rect',
          shape: rectShape,
          style: api.style(),
          styleEmphasis: {
            shadowBlur: 10,
            shadowColor: 'rgba(0, 0, 0, 0.5)'
          }
        };
      },
      encode: {
        x: [1, 2],
        y: 0
      },
      data: seriesData,
      clip: true
    }
  ],

  // Animasyon
  animation: true,
  animationDuration: 500,
  animationEasing: 'cubicOut'
};

// ============================================
// GRAFANA ECHARTS PANEL KODU - BITIS
// ============================================
