import 'dart:convert';
import '../models/cycle.dart';
import '../models/scan_result.dart';

/// Centerpiece interactive HTML visualizer exporter.
class HtmlExporter {
  /// Generates the single self-contained interactive HTML document.
  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
  }) {
    // Prepare cycle lookup maps
    final cycleMap = <String, int>{}; // nodePath -> cycleIndex (1-indexed)
    final cycleChains = <List<String>>[];

    for (var i = 0; i < cycles.length; i++) {
      final cycleIndex = i + 1;
      cycleChains.add(cycles[i].exampleChain);
      for (final file in cycles[i].files) {
        cycleMap[file] = cycleIndex;
      }
    }

    // Build JSON nodes data
    final nodesJsonList = result.files.keys.map((nodePath) {
      final inCycle = cycleMap.containsKey(nodePath);
      final cycleIdx = cycleMap[nodePath];
      return {
        'id': nodePath,
        'label': nodePath,
        'group': inCycle ? 'cycle' : 'normal',
        'cycleIndex': cycleIdx,
        'imports': result.files[nodePath]?.imports ?? [],
        'exports': result.files[nodePath]?.exports ?? [],
      };
    }).toList();

    // Build JSON edges data
    final edgesJsonList = result.edges.map((edge) {
      final isCycleEdge =
          cycleMap.containsKey(edge.from) &&
          cycleMap.containsKey(edge.to) &&
          cycleMap[edge.from] == cycleMap[edge.to];
      return {
        'from': edge.from,
        'to': edge.to,
        'type': edge.type,
        'isCycle': isCycleEdge,
      };
    }).toList();

    final cyclesJsonList = cycles
        .map(
          (c) => {
            'files': c.files,
            'chain': c.exampleChain,
            'extra': c.extraMembers,
          },
        )
        .toList();

    final payload = {
      'packageName': result.packageName,
      'fileCount': result.files.length,
      'edgeCount': result.edges.length,
      'cycleCount': cycles.length,
      'workspacePackageCount': result.workspacePackageCount,
      'isWorkspace': result.isWorkspace,
      'nodes': nodesJsonList,
      'edges': edgesJsonList,
      'cycles': cyclesJsonList,
    };

    final rawJson = jsonEncode(payload);

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_htmlEscape(result.packageName)} - Dependency Graph Visualizer</title>
  <script src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Fira+Code:wght@400;500&display=swap" rel="stylesheet">
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      background-color: #0f172a;
      color: #f8fafc;
      height: 100vh;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }
    header {
      background: rgba(30, 41, 59, 0.85);
      backdrop-filter: blur(12px);
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
      padding: 12px 24px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      z-index: 20;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .brand h1 {
      font-size: 1.15rem;
      font-weight: 700;
      color: #f8fafc;
      letter-spacing: -0.02em;
    }
    .badge {
      background: #3b82f6;
      color: #ffffff;
      padding: 2px 8px;
      border-radius: 6px;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .stats {
      display: flex;
      gap: 16px;
    }
    .stat-card {
      background: rgba(15, 23, 42, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.08);
      padding: 6px 14px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 0.85rem;
    }
    .stat-label {
      color: #94a3b8;
    }
    .stat-value {
      font-weight: 700;
      color: #38bdf8;
    }
    .stat-value.danger {
      color: #f87171;
    }
    .stat-value.success {
      color: #4ade80;
    }
    .main-container {
      display: flex;
      flex: 1;
      position: relative;
      overflow: hidden;
    }
    sidebar {
      width: 340px;
      background: #1e293b;
      border-right: 1px solid rgba(255, 255, 255, 0.1);
      display: flex;
      flex-direction: column;
      z-index: 10;
      transition: transform 0.3s ease;
    }
    .sidebar-header {
      padding: 16px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    }
    .search-box {
      width: 100%;
      background: #0f172a;
      border: 1px solid #334155;
      color: #f8fafc;
      padding: 8px 12px;
      border-radius: 6px;
      font-family: inherit;
      font-size: 0.875rem;
      outline: none;
      transition: border-color 0.2s;
    }
    .search-box:focus {
      border-color: #38bdf8;
    }
    .filter-tools {
      display: flex;
      gap: 8px;
      margin-top: 10px;
    }
    .btn {
      background: #334155;
      color: #f8fafc;
      border: none;
      padding: 6px 12px;
      border-radius: 6px;
      font-size: 0.8rem;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.2s;
    }
    .btn:hover {
      background: #475569;
    }
    .btn.active {
      background: #ef4444;
      color: #ffffff;
    }
    .cycle-list {
      flex: 1;
      overflow-y: auto;
      padding: 12px;
    }
    .cycle-card {
      background: rgba(15, 23, 42, 0.7);
      border: 1px solid rgba(239, 68, 68, 0.3);
      border-radius: 8px;
      padding: 12px;
      margin-bottom: 10px;
      cursor: pointer;
      transition: all 0.2s ease;
    }
    .cycle-card:hover {
      border-color: #ef4444;
      background: rgba(239, 68, 68, 0.1);
      transform: translateY(-1px);
    }
    .cycle-card.active {
      border-color: #ef4444;
      box-shadow: 0 0 12px rgba(239, 68, 68, 0.4);
      background: rgba(239, 68, 68, 0.15);
    }
    .cycle-title {
      font-weight: 600;
      font-size: 0.9rem;
      color: #f87171;
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 6px;
    }
    .cycle-chain {
      font-family: 'Fira Code', monospace;
      font-size: 0.78rem;
      color: #cbd5e1;
      line-height: 1.4;
    }
    .chain-node {
      padding: 2px 0;
      word-break: break-all;
    }
    .chain-arrow {
      color: #ef4444;
      font-weight: bold;
    }
    #network-container {
      flex: 1;
      height: 100%;
      background: radial-gradient(circle at center, #1e293b 0%, #0f172a 100%);
    }
    .node-details-panel {
      position: absolute;
      right: 20px;
      top: 20px;
      width: 320px;
      background: rgba(30, 41, 59, 0.95);
      backdrop-filter: blur(12px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 10px;
      padding: 16px;
      display: none;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5);
      z-index: 15;
    }
    .panel-title {
      font-size: 0.95rem;
      font-weight: 700;
      word-break: break-all;
      color: #38bdf8;
      margin-bottom: 12px;
    }
    .panel-section {
      margin-bottom: 10px;
    }
    .panel-subtitle {
      font-size: 0.75rem;
      font-weight: 600;
      color: #94a3b8;
      text-transform: uppercase;
      margin-bottom: 4px;
    }
    .panel-list {
      font-family: 'Fira Code', monospace;
      font-size: 0.78rem;
      max-height: 120px;
      overflow-y: auto;
      background: #0f172a;
      padding: 6px 8px;
      border-radius: 6px;
    }
    .close-btn {
      position: absolute;
      top: 10px;
      right: 12px;
      background: none;
      border: none;
      color: #94a3b8;
      font-size: 1.2rem;
      cursor: pointer;
    }
    .close-btn:hover {
      color: #f8fafc;
    }
    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.7); }
      70% { box-shadow: 0 0 0 10px rgba(239, 68, 68, 0); }
      100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0); }
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <h1>Dependency Graph Visualizer</h1>
      <span class="badge">${_htmlEscape(result.packageName)}</span>
    </div>
    <div class="stats">
      ${result.isWorkspace ? '<div class="stat-card"><span class="stat-label">Packages:</span><span class="stat-value">${result.workspacePackageCount}</span></div>' : ''}
      <div class="stat-card">
        <span class="stat-label">Files:</span>
        <span class="stat-value">${result.files.length}</span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Edges:</span>
        <span class="stat-value">${result.edges.length}</span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Cycles:</span>
        <span class="stat-value ${cycles.isEmpty ? 'success' : 'danger'}">${cycles.length}</span>
      </div>
    </div>
  </header>

  <div class="main-container">
    <sidebar>
      <div class="sidebar-header">
        <input type="text" id="search" class="search-box" placeholder="Search files...">
        <div class="filter-tools">
          <button class="btn" id="reset-btn">Reset View</button>
          <button class="btn" id="filter-cycles-btn">Show Cycles Only</button>
        </div>
      </div>
      <div class="cycle-list" id="cycle-list">
        <!-- Rendered by JS -->
      </div>
    </sidebar>

    <div id="network-container"></div>

    <div class="node-details-panel" id="details-panel">
      <button class="close-btn" id="panel-close">&times;</button>
      <div class="panel-title" id="panel-filename">filename.dart</div>
      <div class="panel-section">
        <div class="panel-subtitle">Status</div>
        <div id="panel-status">Normal</div>
      </div>
      <div class="panel-section">
        <div class="panel-subtitle">Direct Imports (Outgoing)</div>
        <div class="panel-list" id="panel-imports">None</div>
      </div>
      <div class="panel-section">
        <div class="panel-subtitle">Importers (Incoming)</div>
        <div class="panel-list" id="panel-importers">None</div>
      </div>
    </div>
  </div>

  <script id="graph-data" type="application/json">
    $rawJson
  </script>

  <script>
    const graphData = JSON.parse(document.getElementById('graph-data').textContent);

    const container = document.getElementById('network-container');
    const searchInput = document.getElementById('search');
    const resetBtn = document.getElementById('reset-btn');
    const filterCyclesBtn = document.getElementById('filter-cycles-btn');
    const cycleListContainer = document.getElementById('cycle-list');
    const detailsPanel = document.getElementById('details-panel');
    const panelFilename = document.getElementById('panel-filename');
    const panelStatus = document.getElementById('panel-status');
    const panelImports = document.getElementById('panel-imports');
    const panelImporters = document.getElementById('panel-importers');
    const panelClose = document.getElementById('panel-close');

    let showOnlyCycles = false;
    let selectedCycleIndex = null;

    // Convert raw JSON data to Vis-network DataSets
    const nodes = new vis.DataSet(
      graphData.nodes.map(n => {
        const isCycle = n.group === 'cycle';
        return {
          id: n.id,
          label: n.label,
          shape: 'box',
          margin: 10,
          font: { face: 'Fira Code', size: 12, color: isCycle ? '#fee2e2' : '#e2e8f0' },
          color: {
            background: isCycle ? '#991b1b' : '#1e293b',
            border: isCycle ? '#ef4444' : '#334155',
            highlight: {
              background: isCycle ? '#dc2626' : '#0284c7',
              border: isCycle ? '#f87171' : '#38bdf8'
            }
          },
          borderWidth: isCycle ? 2 : 1,
          cycleIndex: n.cycleIndex
        };
      })
    );

    const edges = new vis.DataSet(
      graphData.edges.map(e => ({
        from: e.from,
        to: e.to,
        arrows: 'to',
        dashes: e.type === 'export',
        color: {
          color: e.isCycle ? '#ef4444' : '#475569',
          highlight: '#38bdf8',
          hover: '#38bdf8'
        },
        width: e.isCycle ? 2 : 1
      }))
    );

    const options = {
      nodes: {
        shadow: true
      },
      edges: {
        smooth: {
          type: 'cubicBezier',
          forceDirection: 'horizontal',
          roundness: 0.4
        }
      },
      physics: {
        solver: 'forceAtlas2Based',
        forceAtlas2Based: {
          gravitationalConstant: -45,
          centralGravity: 0.01,
          springLength: 120,
          springConstant: 0.08
        },
        stabilization: { iterations: 150 }
      },
      interaction: {
        hover: true,
        tooltipDelay: 200
      }
    };

    const network = new vis.Network(container, { nodes, edges }, options);

    // Render sidebar cycles
    function renderCyclesSidebar() {
      if (graphData.cycles.length === 0) {
        cycleListContainer.innerHTML = '<div style="color: #4ade80; text-align: center; padding: 20px; font-weight: 500;">✓ No circular dependencies detected!</div>';
        return;
      }

      cycleListContainer.innerHTML = graphData.cycles.map((cycle, idx) => {
        const cycleNum = idx + 1;
        const chainHtml = cycle.chain.map((step, i) => {
          if (i === 0) return `<div class="chain-node">\${step}</div>`;
          return `<div class="chain-node"><span class="chain-arrow">&rarr;</span> \${step}</div>`;
        }).join('');

        return `
          <div class="cycle-card" data-cycle-idx="\${cycleNum}">
            <div class="cycle-title">
              <span>Cycle #\${cycleNum}</span>
              <span>\${cycle.files.length} files</span>
            </div>
            <div class="cycle-chain">\${chainHtml}</div>
          </div>
        `;
      }).join('');

      document.querySelectorAll('.cycle-card').forEach(card => {
        card.addEventListener('click', () => {
          const idx = parseInt(card.getAttribute('data-cycle-idx'), 10);
          focusCycle(idx);
        });
      });
    }

    renderCyclesSidebar();

    function focusCycle(cycleIdx) {
      selectedCycleIndex = cycleIdx;

      document.querySelectorAll('.cycle-card').forEach(card => {
        const idx = parseInt(card.getAttribute('data-cycle-idx'), 10);
        if (idx === cycleIdx) {
          card.classList.add('active');
        } else {
          card.classList.remove('active');
        }
      });

      const cycleInfo = graphData.cycles[cycleIdx - 1];
      if (!cycleInfo) return;

      const targetNodes = new Set(cycleInfo.files);

      network.selectNodes(Array.from(targetNodes));
      network.focus(cycleInfo.files[0], {
        scale: 1.1,
        animation: { duration: 800, easingFunction: 'easeInOutQuad' }
      });
    }

    // Search filter logic
    searchInput.addEventListener('input', (e) => {
      const term = e.target.value.toLowerCase().trim();
      if (!term) {
        nodes.forEach(n => nodes.update({ id: n.id, hidden: false }));
        return;
      }
      nodes.forEach(n => {
        const matches = n.id.toLowerCase().includes(term);
        nodes.update({ id: n.id, hidden: !matches });
      });
    });

    resetBtn.addEventListener('click', () => {
      selectedCycleIndex = null;
      showOnlyCycles = false;
      filterCyclesBtn.classList.remove('active');
      searchInput.value = '';
      document.querySelectorAll('.cycle-card').forEach(c => c.classList.remove('active'));
      nodes.forEach(n => nodes.update({ id: n.id, hidden: false }));
      edges.forEach(e => edges.update({ id: e.id, hidden: false }));
      network.fit({ animation: { duration: 500 } });
      detailsPanel.style.display = 'none';
    });

    filterCyclesBtn.addEventListener('click', () => {
      showOnlyCycles = !showOnlyCycles;
      filterCyclesBtn.classList.toggle('active', showOnlyCycles);

      const cycleFileSet = new Set();
      graphData.cycles.forEach(c => c.files.forEach(f => cycleFileSet.add(f)));

      nodes.forEach(n => {
        if (showOnlyCycles) {
          nodes.update({ id: n.id, hidden: !cycleFileSet.has(n.id) });
        } else {
          nodes.update({ id: n.id, hidden: false });
        }
      });
    });

    // Node details panel on selection
    network.on('click', (params) => {
      if (params.nodes.length > 0) {
        const nodeId = params.nodes[0];
        showNodeDetails(nodeId);
      } else {
        detailsPanel.style.display = 'none';
      }
    });

    panelClose.addEventListener('click', () => {
      detailsPanel.style.display = 'none';
    });

    function showNodeDetails(nodeId) {
      const nodeData = graphData.nodes.find(n => n.id === nodeId);
      if (!nodeData) return;

      panelFilename.textContent = nodeId;

      if (nodeData.group === 'cycle') {
        panelStatus.innerHTML = `<span style="color: #f87171; font-weight: 600;">In Cycle #\${nodeData.cycleIndex}</span>`;
      } else {
        panelStatus.innerHTML = `<span style="color: #4ade80; font-weight: 500;">Normal</span>`;
      }

      // Incoming & Outgoing edges
      const outgoing = graphData.edges.filter(e => e.from === nodeId).map(e => e.to);
      const incoming = graphData.edges.filter(e => e.to === nodeId).map(e => e.from);

      panelImports.innerHTML = outgoing.length > 0
        ? outgoing.map(f => `<div>\${f}</div>`).join('')
        : '<div>None</div>';

      panelImporters.innerHTML = incoming.length > 0
        ? incoming.map(f => `<div>\${f}</div>`).join('')
        : '<div>None</div>';

      detailsPanel.style.display = 'block';
    }
  </script>
</body>
</html>
''';
  }

  static String _htmlEscape(String str) {
    return str
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
