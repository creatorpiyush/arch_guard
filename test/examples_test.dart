import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:arch_guard/src/cli/init_command.dart';
import 'package:arch_guard/src/cli/run.dart';
import 'package:test/test.dart';

/// Keeps example/cases/* in line with what their READMEs promise.
void main() {
  Future<ArchAnalysis> run(String name) =>
      ArchAnalysis.run(projectPath: 'example/cases/$name');

  test('every failing case exits 1, testing exits 0', () async {
    for (final name in [
      'cycles',
      'layers',
      'presets',
      'hybrid_layout',
      'forbidden_packages',
      'metrics',
      'workspace_rules',
      'baseline',
      'scan_options',
    ]) {
      expect(await runCli(['example/cases/$name']), 1, reason: name);
    }
    expect(await runCli(['example/cases/testing']), 0);
  });

  test(
    'cycles: one hint breaks, one shrinks; both over max_scc_size',
    () async {
      final a = await run('cycles');
      expect(a.cycles.map((c) => c.scc!.suggestedBreak!.describe()), [
        'lib/account/profile.dart:1 -> lib/account/settings.dart '
            '(shrinks the group from 3 to 2 files)',
        'lib/shop/cart.dart:1 -> lib/shop/checkout.dart (breaks the cycle)',
      ]);
      expect(a.oversizedCycles, hasLength(2));
    },
  );

  test('layers and presets: one violation, legacy ignored', () async {
    final layers = await run('layers');
    expect(layers.layerViolations.map((v) => v.sourceFile), [
      'lib/presentation/profile_page.dart',
    ]);
    final presets = await run('presets');
    expect(presets.layerViolations.map((v) => v.sourceFile), [
      'lib/features/auth/presentation/login_page.dart',
    ]);
  });

  test(
    'hybrid_layout: init writes the committed config; bloc -> UI fails',
    () async {
      const dir = 'example/cases/hybrid_layout';
      final detected = LayoutDetector.detect(dir);
      expect(detected.preset, 'riverpod');
      expect(detected.blocFolders, ['bloc']);
      final yaml = buildInitConfig(
        preset: detected.preset,
        reason: detected.reason,
        rootPath: dir,
        blocFolders: detected.blocFolders,
      );
      // Windows checkouts may turn the committed file's LF into CRLF.
      final committed = File('$dir/arch_guard.yaml').readAsStringSync();
      expect(committed.replaceAll('\r\n', '\n'), yaml);

      final a = await run('hybrid_layout');
      expect(
        a.layerViolations.map((v) => '${v.sourceLayer} ${v.targetLayer}'),
        ['bloc presentation'],
      );
    },
  );

  test('forbidden packages, metrics and workspace rules', () async {
    final pkg = await run('forbidden_packages');
    expect(pkg.packageViolations.map((v) => '${v.sourceFile} ${v.uri}'), {
      'lib/data/serializer.dart dart:mirrors',
      'lib/domain/clock.dart dart:io',
    });
    final metrics = await run('metrics');
    expect(metrics.metricViolations.map((v) => '${v.file} ${v.metric}'), {
      'lib/app.dart fan_out',
      'lib/utils.dart fan_in',
    });
    final ws = await run('workspace_rules');
    expect(
      ws.workspaceViolations.single.sourceFile,
      'packages/core/lib/core.dart',
    );
  });

  test('scan_options: --exclude passes, --scan-dir bin fails', () async {
    const dir = 'example/cases/scan_options';
    const exclude = ['--exclude', 'lib/**/generated/**'];
    expect(await runCli([dir, ...exclude]), 0);
    expect(
      await runCli([dir, '--scan-dir', 'lib', '--scan-dir', 'bin', ...exclude]),
      1,
    );
  });

  test('baseline: the cycle is known, the layer violation is new', () async {
    final a = await run('baseline');
    expect(a.baseline!.knownCycles, hasLength(1));
    expect(a.newCycles, isEmpty);
    expect(a.newLayerViolations.single.sourceFile, 'lib/domain/order.dart');
  });
}
