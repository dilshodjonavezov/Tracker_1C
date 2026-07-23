const fs = require('fs');
const path = require('path');
const XLSX = require('/tmp/gps-map-tool/node_modules/xlsx');

const [, , inputPath, outputPath] = process.argv;

if (!inputPath || !outputPath) {
  console.error('Usage: node generate_gps_map.js <input.xls> <output.html>');
  process.exit(1);
}

const workbook = XLSX.readFile(inputPath);
const sheet = workbook.Sheets[workbook.SheetNames[0]];
const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: null });

const points = rows
  .slice(1)
  .map((row, index) => {
    const time = row[0] ? String(row[0]) : null;
    const latRaw = row[3];
    const lonRaw = row[4];
    const lat = parseCoordinate(latRaw);
    const lon = parseCoordinate(lonRaw);

    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return null;
    }

    return {
      index: index + 1,
      time,
      lat,
      lon,
    };
  })
  .filter(Boolean);

if (points.length < 2) {
  console.error('Not enough valid coordinates found in the spreadsheet.');
  process.exit(1);
}

const title = path.basename(inputPath).replace(path.extname(inputPath), '');
const html = buildHtml(title, points);

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, html, 'utf8');

console.log(`Created ${outputPath} with ${points.length} points.`);

function parseCoordinate(value) {
  if (typeof value === 'number') {
    return value;
  }

  if (typeof value !== 'string') {
    return NaN;
  }

  return Number.parseFloat(value.replace(',', '.').trim());
}

function buildHtml(title, points) {
  const pointsJson = JSON.stringify(points);

  return `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${escapeHtml(title)} - GPS Map</title>
  <link
    rel="stylesheet"
    href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
    integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
    crossorigin=""
  />
  <style>
    :root {
      --bg: #f4f1ea;
      --panel: rgba(255, 252, 246, 0.88);
      --text: #2d241d;
      --muted: #6f6358;
      --border: rgba(76, 58, 43, 0.14);
      --shadow: 0 24px 60px rgba(59, 42, 25, 0.12);
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(255, 198, 120, 0.18), transparent 28%),
        linear-gradient(180deg, #f8f5ef 0%, #ebe5d8 100%);
      color: var(--text);
    }

    .layout {
      min-height: 100vh;
      display: grid;
      grid-template-columns: 360px 1fr;
      gap: 18px;
      padding: 18px;
    }

    .panel {
      background: var(--panel);
      backdrop-filter: blur(14px);
      border: 1px solid var(--border);
      border-radius: 24px;
      box-shadow: var(--shadow);
      overflow: hidden;
    }

    .sidebar {
      padding: 24px;
      display: flex;
      flex-direction: column;
      gap: 18px;
    }

    h1 {
      margin: 0;
      font-size: 28px;
      line-height: 1.05;
      letter-spacing: -0.04em;
    }

    .subtitle {
      margin: 0;
      color: var(--muted);
      line-height: 1.5;
    }

    .stat {
      padding: 14px 16px;
      border: 1px solid var(--border);
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.45);
    }

    .stat-label {
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--muted);
      margin-bottom: 6px;
    }

    .stat-value {
      font-size: 24px;
      font-weight: 700;
    }

    .legend {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 16px;
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.52);
      border: 1px solid var(--border);
    }

    .legend-bar {
      flex: 1;
      height: 10px;
      border-radius: 999px;
      background: linear-gradient(90deg, #2d6cdf 0%, #30c7ff 20%, #54df85 45%, #ffe04b 70%, #ff8f2b 85%, #b62222 100%);
    }

    .map-wrap {
      position: relative;
      min-height: calc(100vh - 36px);
    }

    #map {
      position: absolute;
      inset: 0;
    }

    .leaflet-container {
      background: #e7dfd0;
    }

    @media (max-width: 920px) {
      .layout {
        grid-template-columns: 1fr;
      }

      .map-wrap {
        min-height: 70vh;
      }
    }
  </style>
</head>
<body>
  <div class="layout">
    <aside class="panel sidebar">
      <div>
        <h1>${escapeHtml(title)}</h1>
        <p class="subtitle">Локальная визуализация GPS-точек из Excel. Линии соединяют точки по порядку, цвет меняется от старта к финишу примерно как на твоём примере.</p>
      </div>

      <div class="stat">
        <div class="stat-label">Точек</div>
        <div class="stat-value" id="pointsCount"></div>
      </div>

      <div class="stat">
        <div class="stat-label">Старт</div>
        <div class="stat-value" id="startTime" style="font-size: 18px;"></div>
      </div>

      <div class="stat">
        <div class="stat-label">Финиш</div>
        <div class="stat-value" id="endTime" style="font-size: 18px;"></div>
      </div>

      <div class="legend">
        <span>Старт</span>
        <div class="legend-bar"></div>
        <span>Финиш</span>
      </div>
    </aside>

    <main class="panel map-wrap">
      <div id="map"></div>
    </main>
  </div>

  <script
    src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
    integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
    crossorigin=""
  ></script>
  <script>
    const points = ${pointsJson};

    document.getElementById('pointsCount').textContent = points.length.toLocaleString('ru-RU');
    document.getElementById('startTime').textContent = points[0].time || 'Нет данных';
    document.getElementById('endTime').textContent = points[points.length - 1].time || 'Нет данных';

    const map = L.map('map', {
      zoomControl: true,
      preferCanvas: true,
    });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(map);

    const latLngs = points.map((point) => [point.lat, point.lon]);
    map.fitBounds(latLngs, { padding: [40, 40] });

    for (let i = 0; i < points.length - 1; i += 1) {
      const start = points[i];
      const end = points[i + 1];
      const progress = i / Math.max(points.length - 2, 1);

      L.polyline(
        [
          [start.lat, start.lon],
          [end.lat, end.lon],
        ],
        {
          color: gradientColor(progress),
          weight: 4,
          opacity: 0.95,
          lineCap: 'round',
          lineJoin: 'round',
        }
      ).addTo(map);
    }

    L.circleMarker(latLngs[0], {
      radius: 7,
      color: '#173b8c',
      weight: 3,
      fillColor: '#61b8ff',
      fillOpacity: 1,
    }).addTo(map).bindPopup('<b>Старт</b><br>' + escapeHtml(points[0].time || ''));

    L.circleMarker(latLngs[latLngs.length - 1], {
      radius: 7,
      color: '#7b130d',
      weight: 3,
      fillColor: '#ff9350',
      fillOpacity: 1,
    }).addTo(map).bindPopup('<b>Финиш</b><br>' + escapeHtml(points[points.length - 1].time || ''));

    const sampledPoints = points.filter((_, index) => index % 80 === 0);
    sampledPoints.forEach((point, index) => {
      const progress = index / Math.max(sampledPoints.length - 1, 1);
      L.circleMarker([point.lat, point.lon], {
        radius: 2.5,
        stroke: false,
        fillColor: gradientColor(progress),
        fillOpacity: 0.85,
      }).addTo(map);
    });

    function gradientColor(progress) {
      const hue = 220 - (progress * 220);
      return 'hsl(' + hue + ', 82%, 50%)';
    }

    function escapeHtml(value) {
      return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }
  </script>
</body>
</html>`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
