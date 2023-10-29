import 'package:nyxx/src/builders/builder.dart';
import 'package:nyxx/src/errors.dart';
import 'package:nyxx/src/models/message/attachment.dart';

class AttachmentBuilder extends Builder<Attachment> {
  List<int> data;

  String fileName;

  String? description;

  AttachmentBuilder({required this.data, required this.fileName, this.description});

  static Future<AttachmentBuilder> fromFile(dynamic file, {String? description}) => throw JsDisabledError('AttachmentBuilder.fromFile');

  @override
  Map<String, Object?> build() => {
        'filename': fileName,
        if (description != null) 'description': description,
      };
}
