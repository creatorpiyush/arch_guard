import 'scan_result.dart';

/// Coupling numbers for one file, from import/export edges between scanned
/// files (`part` edges and external packages don't count).
class FileMetrics {
  /// Relative path of the file.
  final String file;

  /// Number of scanned files that import or export this file.
  final int fanIn;

  /// Number of scanned files this file imports or exports.
  final int fanOut;

  /// Creates metrics for [file].
  const FileMetrics({
    required this.file,
    required this.fanIn,
    required this.fanOut,
  });

  /// `fanIn + fanOut`; used to rank hotspots.
  int get coupling => fanIn + fanOut;

  /// `fanOut / (fanIn + fanOut)`, from 0 (stable) to 1 (unstable).
  double get instability =>
      coupling == 0 ? 0 : double.parse((fanOut / coupling).toStringAsFixed(2));

  /// JSON form used by the JSON exporter.
  Map<String, dynamic> toJson() => {
    'file': file,
    'fanIn': fanIn,
    'fanOut': fanOut,
    'instability': instability,
  };

  /// Metrics for every scanned file, most coupled first (ties: path).
  static List<FileMetrics> compute(ScanResult result) {
    final out = {for (final f in result.files.keys) f: <String>{}};
    final inc = {for (final f in result.files.keys) f: <String>{}};
    for (final e in result.edges) {
      if (e.type == 'part' || e.from == e.to) continue;
      out[e.from]?.add(e.to);
      inc[e.to]?.add(e.from);
    }
    return [
      for (final f in result.files.keys)
        FileMetrics(file: f, fanIn: inc[f]!.length, fanOut: out[f]!.length),
    ]..sort((a, b) {
      final c = b.coupling.compareTo(a.coupling);
      return c != 0 ? c : a.file.compareTo(b.file);
    });
  }
}
