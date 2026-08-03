import 'dart:convert';
import '../assets/vis_network_asset.dart';
import '../models/cycle.dart';
import '../models/scan_result.dart';

/// Centerpiece interactive HTML visualizer exporter.
class HtmlExporter {
  /// Prevents an embedded `</script>` (or `<!--`) sequence inside inlined JS
  /// from prematurely terminating the surrounding HTML `<script>` block.
  static String _escapeInlineScript(String js) {
    return js.replaceAll('</script', '<\\/script').replaceAll('<!--', '<\\!--');
  }

  /// Generates the single self-contained interactive HTML document.
  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
    String scope = 'cycles',
    bool offline = false,
  }) {
    final cyclicFiles = cycles.expand((c) => c.files).toSet();

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

    // Determine nodes to export based on scope
    final Set<String> targetNodes;
    if (scope == 'cycles') {
      if (cyclicFiles.isEmpty) {
        // If no cycles found, include top 20 files as context sample
        targetNodes = result.files.keys.take(20).toSet();
      } else {
        // Include cyclic files + 1 hop neighbor context
        targetNodes = <String>{...cyclicFiles};
        for (final edge in result.edges) {
          if (cyclicFiles.contains(edge.from) ||
              cyclicFiles.contains(edge.to)) {
            targetNodes.add(edge.from);
            targetNodes.add(edge.to);
          }
        }
      }
    } else {
      targetNodes = result.files.keys.toSet();
    }

    // Build JSON nodes data
    final nodesJsonList = result.files.keys
        .where((path) => targetNodes.contains(path))
        .map((nodePath) {
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
        })
        .toList();

    // Build JSON edges data
    final edgesJsonList = result.edges
        .where(
          (edge) =>
              targetNodes.contains(edge.from) && targetNodes.contains(edge.to),
        )
        .map((edge) {
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
        })
        .toList();

    final cyclesJsonList = cycles
        .map(
          (c) => {
            'files': c.files,
            'chain': c.exampleChain,
            'extra': c.extraMembers,
            if (c.scc != null) 'scc': c.scc!.toJson(),
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
      'scope': scope,
      'nodes': nodesJsonList,
      'edges': edgesJsonList,
      'cycles': cyclesJsonList,
    };

    final rawJson = jsonEncode(payload);

    final visNetworkTag = offline
        ? '<script>\n${_escapeInlineScript(visNetworkMinJs)}\n</script>'
        : '<script src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>';

    final fontsTag = offline
        ? '<!-- --offline: Google Fonts skipped, using system font fallback -->'
        : '<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Fira+Code:wght@400;500&display=swap" rel="stylesheet">';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_htmlEscape(result.packageName)} - Dependency Graph Visualizer</title>
  $visNetworkTag
  $fontsTag
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
      display: flex;
      align-items: center;
      gap: 8px;
      background: rgba(255, 255, 255, 0.05);
      padding: 4px 12px;
      border-radius: 6px;
      font-size: 0.85rem;
    }
    .stat-value {
      font-weight: 700;
      color: #60a5fa;
    }
    .stat-value.danger {
      color: #f87171;
    }
    main {
      flex: 1;
      display: flex;
      position: relative;
    }
    #sidebar {
      width: 320px;
      background: #1e293b;
      border-right: 1px solid rgba(255, 255, 255, 0.1);
      display: flex;
      flex-direction: column;
      z-index: 10;
    }
    .sidebar-header {
      padding: 16px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
    }
    .search-box {
      width: 100%;
      padding: 8px 12px;
      border-radius: 6px;
      border: 1px solid rgba(255, 255, 255, 0.15);
      background: #0f172a;
      color: #fff;
      font-size: 0.85rem;
      outline: none;
    }
    .search-box:focus {
      border-color: #3b82f6;
    }
    .cycle-list {
      flex: 1;
      overflow-y: auto;
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .cycle-card {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 8px;
      padding: 12px;
      cursor: pointer;
      transition: all 0.2s ease;
    }
    .cycle-card:hover {
      background: rgba(255, 255, 255, 0.08);
      border-color: rgba(255, 255, 255, 0.2);
    }
    .cycle-card.active {
      border-color: #ef4444;
      background: rgba(239, 68, 68, 0.1);
    }
    .cycle-title {
      font-size: 0.85rem;
      font-weight: 600;
      color: #f87171;
      margin-bottom: 6px;
      display: flex;
      justify-content: space-between;
    }
    .cycle-chain {
      font-family: 'Fira Code', monospace;
      font-size: 0.75rem;
      color: #94a3b8;
      word-break: break-all;
    }
    .chain-node {
      padding: 2px 0;
    }
    .chain-arrow {
      color: #ef4444;
    }
    #mynetwork {
      flex: 1;
      height: 100%;
      background: #0f172a;
    }
    #details-panel {
      position: absolute;
      top: 20px;
      right: 20px;
      width: 340px;
      background: rgba(30, 41, 59, 0.92);
      backdrop-filter: blur(16px);
      border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 12px;
      padding: 20px;
      z-index: 30;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5);
      display: none;
    }
    .panel-header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 12px;
    }
    .panel-filename {
      font-family: 'Fira Code', monospace;
      font-size: 0.85rem;
      font-weight: 600;
      color: #38bdf8;
      word-break: break-all;
    }
    .panel-close {
      background: none;
      border: none;
      color: #94a3b8;
      font-size: 1.2rem;
      cursor: pointer;
    }
    .panel-close:hover {
      color: #fff;
    }
    .panel-section {
      margin-top: 12px;
    }
    .panel-section-title {
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #94a3b8;
      margin-bottom: 4px;
    }
    .panel-list {
      font-family: 'Fira Code', monospace;
      font-size: 0.75rem;
      color: #cbd5e1;
      max-height: 120px;
      overflow-y: auto;
    }
    .toolbar {
      position: absolute;
      bottom: 20px;
      left: 340px;
      display: flex;
      gap: 8px;
      z-index: 20;
    }
    .btn {
      background: #1e293b;
      color: #fff;
      border: 1px solid rgba(255, 255, 255, 0.15);
      padding: 8px 14px;
      border-radius: 6px;
      font-size: 0.85rem;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
    }
    .btn:hover {
      background: #334155;
    }
    .btn.active {
      background: #ef4444;
      border-color: #ef4444;
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
      <div class="stat-card">Files: <span class="stat-value">${result.files.length}</span></div>
      <div class="stat-card">Edges: <span class="stat-value">${result.edges.length}</span></div>
      <div class="stat-card">Cycles: <span class="stat-value ${cycles.isNotEmpty ? 'danger' : ''}">${cycles.length}</span></div>
    </div>
  </header>
  <main>
    <div id="sidebar">
      <div class="sidebar-header">
        <input type="text" id="search-input" class="search-box" placeholder="Filter files by path..." />
      </div>
      <div class="cycle-list" id="cycle-list"></div>
    </div>
    <div id="mynetwork"></div>

    <div class="toolbar">
      <button class="btn" id="reset-btn">Reset View</button>
      <button class="btn" id="filter-cycles-btn">Focus Cycles Only</button>
    </div>

    <div id="details-panel">
      <div class="panel-header">
        <div class="panel-filename" id="panel-filename">lib/main.dart</div>
        <button class="panel-close" id="panel-close">&times;</button>
      </div>
      <div class="panel-section">
        <div class="panel-section-title">Status</div>
        <div id="panel-status">In Cycle #1</div>
      </div>
      <div class="panel-section">
        <div class="panel-section-title">Imports</div>
        <div class="panel-list" id="panel-imports"></div>
      </div>
      <div class="panel-section">
        <div class="panel-section-title">Imported By</div>
        <div class="panel-list" id="panel-importers"></div>
      </div>
    </div>
  </main>

  <script id="graph-data" type="application/json">
    $rawJson
  </script>

  <script>
    const graphData = JSON.parse(document.getElementById('graph-data').textContent);

    const container = document.getElementById('mynetwork');
    const searchInput = document.getElementById('search-input');
    const cycleListContainer = document.getElementById('cycle-list');
    const resetBtn = document.getElementById('reset-btn');
    const filterCyclesBtn = document.getElementById('filter-cycles-btn');

    const detailsPanel = document.getElementById('details-panel');
    const panelFilename = document.getElementById('panel-filename');
    const panelStatus = document.getElementById('panel-status');
    const panelImports = document.getElementById('panel-imports');
    const panelImporters = document.getElementById('panel-importers');
    const panelClose = document.getElementById('panel-close');

    let selectedCycleIndex = null;
    let showOnlyCycles = false;

    // Convert nodes for vis-network
    const nodes = new vis.DataSet(graphData.nodes.map(n => {
      const isCycle = n.group === 'cycle';
      return {
        id: n.id,
        label: n.id.split('/').pop(),
        title: n.id,
        shape: isCycle ? 'dot' : 'dot',
        size: isCycle ? 16 : 8,
        color: isCycle ? {
          background: '#ef4444',
          border: '#b91c1c',
          highlight: { background: '#f87171', border: '#ef4444' }
        } : {
          background: '#38bdf8',
          border: '#0284c7',
          highlight: { background: '#7dd3fc', border: '#38bdf8' }
        },
        font: { color: '#cbd5e1', size: 12 }
      };
    }));

    // Convert edges for vis-network
    const edges = new vis.DataSet(graphData.edges.map(e => ({
      id: `\${e.from}->\${e.to}`,
      from: e.from,
      to: e.to,
      arrows: 'to',
      color: e.isCycle ? { color: '#ef4444', highlight: '#f87171' } : { color: '#334155', highlight: '#64748b' },
      width: e.isCycle ? 2 : 1,
      dashes: e.type === 'export'
    })));

    const options = {
      nodes: {
        borderWidth: 2,
        shadow: true
      },
      edges: {
        smooth: {
          type: 'continuous',
          roundness: 0.2
        }
      },
      physics: {
        solver: 'forceAtlas2Based',
        forceAtlas2Based: {
          gravitationalConstant: -26,
          centralGravity: 0.005,
          springLength: 100,
          springConstant: 0.18
        },
        maxVelocity: 50,
        minVelocity: 0.75,
        stabilization: {
          enabled: true,
          iterations: 150
        }
      },
      interaction: {
        hover: true,
        tooltipDelay: 200
      }
    };

    const network = new vis.Network(container, { nodes, edges }, options);

    // Freeze physics once the initial layout settles, instead of letting
    // forceAtlas2Based keep recalculating forces every frame indefinitely.
    network.once('stabilizationIterationsDone', () => {
      network.setOptions({ physics: false });
    });

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
