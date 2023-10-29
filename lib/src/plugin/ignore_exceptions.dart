import 'package:nyxx/src/errors.dart';
import 'package:nyxx/src/plugin/plugin.dart';

/// A global instance of the [IgnoreExceptions] plugin.
final ignoreExceptions = IgnoreExceptions();

/// A plugin that prevents errors from crashing the program, instead logging them to the console.
class IgnoreExceptions extends NyxxPlugin {
  IgnoreExceptions() {
    throw JsDisabledError('IgnoreExceptions');
  }
}
