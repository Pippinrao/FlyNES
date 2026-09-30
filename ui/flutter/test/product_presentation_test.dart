import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/app/product_presentation.dart';

void main() {
  test(
    'only the first post-mutation frame with matching raster timing reveals',
    () {
      final fence = ProductPresentation()..request('hall-2');
      expect(fence.rasterized([10]), isNull);
      fence.frameStarted('hall-2', 11);
      expect(fence.rasterized([9, 10]), isNull);
      expect(fence.rasterized([11, 12]), 'hall-2');
      expect(fence.rasterized([11]), isNull);
    },
  );
  test('replacement rejects old scheduled frame and old raster batch', () {
    final fence = ProductPresentation()..request('settings-1');
    fence.frameStarted('settings-1', 20);
    fence.request('hall-2');
    fence.frameStarted('settings-1', 21);
    expect(fence.rasterized([20, 21]), isNull);
    fence.frameStarted('hall-2', 22);
    expect(fence.rasterized([22]), 'hall-2');
  });
  test(
    'a later same-context raster can replace a frame lost with its surface',
    () {
      final fence = ProductPresentation()..request('hall-2');
      fence.frameStarted('hall-2', 30);
      expect(fence.rasterized([29]), isNull);
      expect(fence.rasterized([31]), 'hall-2');
    },
  );
}
