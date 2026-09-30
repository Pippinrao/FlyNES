/// Correlates a post-mutation framework frame with its actual raster timing.
class ProductPresentation {
  String? token;
  int? frame;
  int? rasterFrame;
  void request(String value) {
    token = value;
    frame = null;
  }

  void frameStarted(String value, int number) {
    if (value == token && frame == null && number > 0) frame = number;
  }

  String? rasterized(Iterable<int> numbers) {
    if (frame == null) return null;
    final matches = numbers.where((number) => number >= frame!);
    if (matches.isEmpty) return null;
    rasterFrame = matches.first;
    final ready = token;
    token = null;
    frame = null;
    return ready;
  }
}
