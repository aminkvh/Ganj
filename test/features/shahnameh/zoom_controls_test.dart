import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/ui/zoom_controls.dart';

void main() {
  test('zoomBy scales around the middle of the view', () {
    final c = TransformationController();
    zoomBy(c, 0.5, const Size(400, 800), min: 0.1, max: 3);
    expect(c.value.getMaxScaleOnAxis(), closeTo(0.5, 1e-9));
    // The middle stays put.
    final mid = MatrixUtils.transformPoint(c.value, const Offset(200, 400));
    expect(mid.dx, closeTo(200, 1e-6));
    expect(mid.dy, closeTo(400, 1e-6));
  });

  test('zoomBy respects the limits', () {
    final c = TransformationController();
    zoomBy(c, 0.01, const Size(400, 800), min: 0.2, max: 3);
    expect(c.value.getMaxScaleOnAxis(), closeTo(0.2, 1e-9));
  });

  test('fitMatrix fits the content inside the view', () {
    final m = fitMatrix(const Size(400, 800), const Size(4000, 1000));
    final s = m.getMaxScaleOnAxis();
    expect(4000 * s, lessThanOrEqualTo(400));
  });
}
