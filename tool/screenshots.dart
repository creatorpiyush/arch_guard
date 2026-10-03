// Regenerates the README / docs screenshots in docs/images/.
//
// Runs arch_guard from source on example/sample_project, then drives a
// headless Chrome over the DevTools protocol to capture the interactive HTML
// graph and the colored terminal report.
//
// Usage: dart run tool/screenshots.dart
// Set CHROME to the Chrome/Chromium binary if it is not found automatically.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final _repoRoot = p.normalize(p.join(p.dirname(Platform.script.path), '..'));
final _sampleProject = p.join(_repoRoot, 'example', 'sample_project');
final _imagesDir = p.join(_repoRoot, 'docs', 'images');

Future<void> main() async {
  final temp = Directory.systemTemp.createTempSync('arch_guard_shots_');
  try {
    Directory(_imagesDir).createSync(recursive: true);

    await _archGuard(['-f', 'html', '-o', temp.path, '--offline']);
    final graphHtml = p.join(temp.path, 'dependency_graph.html');

    final text = await _archGuard([]);
    final terminalHtml = p.join(temp.path, 'terminal.html');
    File(terminalHtml).writeAsStringSync(_terminalPage(text));

    final chrome = await _Chrome.launch(temp.path);
    try {
      await chrome.capture(
        url: Uri.file(graphHtml).toString(),
        out: p.join(_imagesDir, 'graph.png'),
        width: 1400,
        height: 850,
        settle: const Duration(seconds: 5),
      );
      await chrome.capture(
        url: Uri.file(terminalHtml).toString(),
        out: p.join(_imagesDir, 'terminal.png'),
        width: 1100,
        height: 300,
        fullPage: true,
      );
    } finally {
      chrome.close();
    }
    print('Wrote graph.png and terminal.png to $_imagesDir');
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// Runs arch_guard from source in the sample project and returns stdout.
Future<String> _archGuard(List<String> args) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'run',
    p.join(_repoRoot, 'bin', 'arch_guard.dart'),
    '--no-fail-on-cycle',
    ...args,
  ], workingDirectory: _sampleProject);
  if (result.exitCode > 1) {
    throw StateError('arch_guard failed:\n${result.stderr}');
  }
  return '${result.stderr}${result.stdout}';
}

/// Wraps ANSI-colored [text] in a terminal-looking HTML page.
String _terminalPage(String text) {
  const colors = {
    '31': '#ff6b6b',
    '32': '#69db7c',
    '33': '#ffd43b',
    '36': '#66d9e8',
  };
  final body = StringBuffer();
  var open = 0;
  final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(text);
  for (final part in escaped.split('\x1B[')) {
    final m = RegExp(r'^([\d;]*)m').firstMatch(part);
    if (m == null) {
      body.write(part);
      continue;
    }
    for (final code in m.group(1)!.split(';')) {
      if (code == '0' || code.isEmpty) {
        body.write('</span>' * open);
        open = 0;
      } else if (code == '1') {
        body.write('<span style="font-weight:bold">');
        open++;
      } else if (code == '2') {
        body.write('<span style="opacity:.6">');
        open++;
      } else if (colors[code] case final color?) {
        body.write('<span style="color:$color">');
        open++;
      }
    }
    body.write(part.substring(m.end));
  }
  body.write('</span>' * open);

  return '''
<!doctype html>
<meta charset="utf-8">
<style>
  body { margin: 0; background: #0f172a; }
  .win { margin: 24px; border-radius: 10px; background: #1e293b;
         box-shadow: 0 10px 30px rgba(0,0,0,.4); overflow: hidden; }
  .bar { padding: 10px 14px; background: #334155; }
  .bar i { display: inline-block; width: 12px; height: 12px;
           border-radius: 50%; margin-right: 6px; }
  pre { margin: 0; padding: 16px 20px; color: #e2e8f0; white-space: pre-wrap;
        font: 14px/1.5 Menlo, Consolas, "DejaVu Sans Mono", monospace; }
</style>
<div class="win">
  <div class="bar"><i style="background:#ff5f56"></i><i style="background:#ffbd2e"></i><i style="background:#27c93f"></i></div>
  <pre><span style="color:#69db7c">\$</span> dart run arch_guard
$body</pre>
</div>
''';
}

/// Minimal headless Chrome driven over the DevTools protocol.
class _Chrome {
  final Process _process;
  final int _port;

  _Chrome(this._process, this._port);

  static Future<_Chrome> launch(String profileDir) async {
    final process = await Process.start(_chromePath(), [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      // The graph lays itself out in animation frames, which Chrome
      // otherwise pauses for tabs it considers in the background.
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding',
      '--remote-debugging-port=0',
      '--user-data-dir=${p.join(profileDir, 'chrome-profile')}',
      'about:blank',
    ]);
    final port = Completer<int>();
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final m = RegExp(
            r'DevTools listening on ws://[^:]+:(\d+)/',
          ).firstMatch(line);
          if (m != null && !port.isCompleted) {
            port.complete(int.parse(m.group(1)!));
          }
        });
    return _Chrome(
      process,
      await port.future.timeout(const Duration(seconds: 20)),
    );
  }

  static String _chromePath() {
    final fromEnv = Platform.environment['CHROME'];
    if (fromEnv != null) return fromEnv;
    const candidates = [
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/usr/bin/google-chrome',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
    ];
    return candidates.firstWhere(
      (c) => File(c).existsSync(),
      orElse: () => throw StateError('Chrome not found; set CHROME.'),
    );
  }

  /// Opens [url] in a new tab and saves a screenshot of it to [out].
  Future<void> capture({
    required String url,
    required String out,
    required int width,
    required int height,
    Duration settle = const Duration(milliseconds: 500),
    bool fullPage = false,
  }) async {
    final client = HttpClient();
    final request = await client.openUrl(
      'PUT',
      Uri.parse('http://127.0.0.1:$_port/json/new?about:blank'),
    );
    final target =
        jsonDecode(await (await request.close()).transform(utf8.decoder).join())
            as Map<String, dynamic>;
    client.close();

    final socket = await WebSocket.connect(
      target['webSocketDebuggerUrl'] as String,
    );
    final pending = <int, Completer<Map<String, dynamic>>>{};
    final loaded = Completer<void>();
    socket.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      if (msg['method'] == 'Page.loadEventFired' && !loaded.isCompleted) {
        loaded.complete();
      }
      final id = msg['id'];
      if (id is int) {
        pending
            .remove(id)
            ?.complete((msg['result'] as Map<String, dynamic>?) ?? const {});
      }
    });
    var nextId = 0;
    Future<Map<String, dynamic>> send(
      String method, [
      Map<String, dynamic> params = const {},
    ]) {
      final id = ++nextId;
      final done = pending[id] = Completer();
      socket.add(jsonEncode({'id': id, 'method': method, 'params': params}));
      return done.future.timeout(const Duration(seconds: 30));
    }

    await send('Page.enable');
    await send('Page.bringToFront');
    await send('Emulation.setDeviceMetricsOverride', {
      'width': width,
      'height': height,
      'deviceScaleFactor': 2,
      'mobile': false,
    });
    await send('Page.navigate', {'url': url});
    await loaded.future.timeout(const Duration(seconds: 30));
    await Future<void>.delayed(settle);

    var clipHeight = height;
    if (fullPage) {
      final metrics = await send('Page.getLayoutMetrics');
      final size = metrics['cssContentSize'] as Map<String, dynamic>;
      clipHeight = (size['height'] as num).ceil();
    }
    final shot = await send('Page.captureScreenshot', {
      'format': 'png',
      'captureBeyondViewport': fullPage,
      'clip': {
        'x': 0,
        'y': 0,
        'width': width,
        'height': clipHeight,
        'scale': 1,
      },
    });
    File(out).writeAsBytesSync(base64Decode(shot['data'] as String));
    await socket.close();
  }

  void close() => _process.kill();
}
