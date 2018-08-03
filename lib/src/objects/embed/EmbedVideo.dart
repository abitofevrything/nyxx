part of nyxx;

/// Video attached to embed. Can contain null elements.
class EmbedVideo {
  /// The embed video's URL.
  String url;

  /// The embed video's height.
  int height;

  /// The embed video's width.
  int width;

  /// The raw object returned by the API
  Map<String, dynamic> raw;

  EmbedVideo._new(this.raw) {
    this.url = raw['url'] as String;
    this.height = raw['height'] as int;
    this.width = raw['width'] as int;
  }
}
