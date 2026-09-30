import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/features/product/product_hall.dart';

void main() {
  testWidgets(
    'U03 real cover decode preserves aspect and replaced pixels evict only prior revision',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('flynes-cover-test-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final file = File('${folder.path}/cover.png');
      Future<void> write(Color color) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 800, 400),
          Paint()..color = color,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(800, 400);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        file.writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }

      Future<ui.Image> show(int revision) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 120,
                height: 90,
                child: ProductCover(
                  item: {'coverPath': file.path, 'coverRevision': revision},
                  title: 'Game',
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('Game'),
          findsOneWidget,
          reason: 'A04 keeps the title placeholder until decoding finishes.',
        );
        for (
          var attempt = 0;
          attempt < 100 &&
              tester.widget<RawImage>(find.byType(RawImage)).image == null;
          ++attempt
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        return tester.widget<RawImage>(find.byType(RawImage)).image!;
      }

      await tester.runAsync(() => write(const Color(0xFFFF0000)));
      final first = await show(1);
      expect(first.width / first.height, closeTo(2, .01));
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final oldKey = await provider.obtainKey(ImageConfiguration.empty);
      final firstPixels = await tester.runAsync(() => first.toByteData());
      expect(firstPixels!.getUint8(0), 255);
      await tester.runAsync(() => write(const Color(0xFF0000FF)));
      final second = await show(2);
      final nextPixels = await tester.runAsync(() => second.toByteData());
      expect(nextPixels!.getUint8(0), 0);
      expect(nextPixels.getUint8(2), 255);
      expect(PaintingBinding.instance.imageCache.containsKey(oldKey), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('U24 overwritten screenshot gets a new decode cache key', (
    tester,
  ) async {
    Future<Object> show(int revision) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              height: 90,
              child: ProductCover(
                item: {
                  'coverPath': '/missing/screenshot.png',
                  'coverRevision': revision,
                },
                title: 'Game',
              ),
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      return image.image.obtainKey(ImageConfiguration.empty);
    }

    final before = await show(1);
    final after = await show(2);
    expect(
      after,
      isNot(before),
      reason:
          'The same path can contain a newer screenshot after returning from a game.',
    );
    expect(
      await show(2),
      after,
      reason: 'Unchanged screenshots reuse their bounded decode.',
    );
  });
}
