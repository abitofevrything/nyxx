import 'package:nyxx/src/errors.dart';
import 'package:nyxx/src/plugin/plugin.dart';

/// A global instance of the [CliIntegration] plugin.
final cliIntegration = CliIntegration();

/// A plugin that lets clients close their session gracefully when the process is terminated.
class CliIntegration extends NyxxPlugin {
  CliIntegration() {
    throw JsDisabledError('CliIntegration');
  }
}
