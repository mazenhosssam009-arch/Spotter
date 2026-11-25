import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/rep_counter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'bench_views_sim_test.dart' as s;
void main() {
  test('probe', () {
    final views = <String, s.Cam>{
      'head end, bench height': s.cams['head end, bench height']!,
      'head end, floor': s.Cam((2.2, 0, -0.35), (-0.2, 0, 0.1), (0, 0, 1)),
      'head end, raised 0.8': s.Cam((2.0, 0, 1.0), (-0.2, 0, 0.1), (0, 0, 1)),
      'foot end, bench height': s.Cam((-2.8, 0, 0.45), (-0.2, 0, 0.1), (0, 0, 1)),
      'foot end, floor': s.Cam((-2.8, 0, -0.35), (-0.2, 0, 0.1), (0, 0, 1)),
      'foot end, raised 0.8': s.Cam((-2.6, 0, 1.0), (-0.2, 0, 0.1), (0, 0, 1)),
      'foot end, raised 1.4': s.Cam((-2.4, 0, 1.6), (-0.2, 0, 0.0), (0, 0, 1)),
    };
    for (final v in views.entries) {
      final row = StringBuffer(v.key.padRight(24));
      final p0 = s.frame(s.benchBody(0, 60), v.value);
      final l = p0.landmarks;
      final sw = (l[11].x - l[12].x).abs(), hw = (l[23].x - l[24].x).abs();
      row.write(' hip/sh ${(hw / sw).toStringAsFixed(2)} zHip-zSh ${((l[23].z + l[24].z) / 2 - (l[11].z + l[12].z) / 2).toStringAsFixed(0)}'
          ' hipsY-shY ${((l[23].y + l[24].y) / 2 - (l[11].y + l[12].y) / 2).toStringAsFixed(0)} |');
      for (final f in [30.0, 45.0, 60.0, 75.0, 85.0, 90.0, 95.0]) {
        final c = RepCounter(exercises.firstWhere((e) => e.name == 'Bench Press'));
        var t = 0.0;
        void fr(double d) => c.update(s.frame(s.benchBody(d, f), v.value), t += 1 / 30);
        for (var i = 0; i < 200; i++) fr(0);
        for (var i = 0; i <= 36; i++) fr(i / 36);
        for (var i = 0; i < 4; i++) fr(1);
        final m = c.flareBottomN == 0 ? -1 : c.flareBottomSum / c.flareBottomN;
        row.write(' ${f.toInt()}:${m.toStringAsFixed(0)}');
      }
      // ignore: avoid_print
      print(row);
    }
  });
}
