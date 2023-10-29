import 'dart:convert';

import 'package:nyxx/src/errors.dart';

class ImageBuilder {
  List<int> data;
  String format;

  ImageBuilder({required this.data, required this.format});

  ImageBuilder.png(this.data) : format = 'png';

  ImageBuilder.jpeg(this.data) : format = 'jpeg';

  ImageBuilder.gif(this.data) : format = 'gif';

  static Future<ImageBuilder> fromFile(dynamic file, {String? format}) => throw JsDisabledError('ImageBuilder.fromFile');

  String buildDataString() => 'data:image/$format;base64,${base64Encode(data)}';

  List<int> buildRawData() => data;
}
