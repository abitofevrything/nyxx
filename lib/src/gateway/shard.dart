import 'dart:async';

import 'package:logging/logging.dart';
import 'package:nyxx/src/api_options.dart';
import 'package:nyxx/src/builders/voice.dart';
import 'package:nyxx/src/client.dart';
import 'package:nyxx/src/errors.dart';
import 'package:nyxx/src/gateway/message.dart';
import 'package:nyxx/src/gateway/shard_runner.dart';
import 'package:nyxx/src/models/gateway/event.dart';
import 'package:nyxx/src/models/gateway/opcode.dart';
import 'package:nyxx/src/models/snowflake.dart';

/// {@template shard}
/// A single connection to Discord's Gateway.
/// {@endtemplate}
class Shard extends Stream<ShardMessage> implements StreamSink<GatewayMessage> {
  /// The ID of this shard.
  final int id;

  /// The isolate this shard's handler is running in.
  Never get isolate => throw JsDisabledError('Shard.isolate');

  /// A future that completes once the shard runner exits.
  @Deprecated('Only present for JS support')
  // ignore: non_constant_identifier_names
  final Future<void> JS_ONLY_exitFuture;

  /// The stream on which events from the runner are received.
  final Stream<dynamic> receiveStream;

  /// The port on which events are sent to the runner.
  Never get sendPort => throw JsDisabledError('Shard.sendPort');

  /// A sink to which events are added to be sent to the runner.
  @Deprecated('Only present for JS support')
  // ignore: non_constant_identifier_names
  final Sink<dynamic> JS_ONLY_sendSink;

  /// The client this [Shard] is for.
  final NyxxGateway client;

  /// The logger used by this shard.
  Logger get logger => Logger('${client.options.loggerName}.Shards[$id]');

  final Completer<void> _doneCompleter = Completer();

  Duration _latency = Duration.zero;

  /// The latency on this shard's connection.
  ///
  /// This is updated for each [HeartbeatAckEvent] received. If no [HeartbeatAckEvent] has been received, this will be [Duration.zero].
  Duration get latency => _latency;

  /// Create a new [Shard].
  Shard(this.id, this.JS_ONLY_exitFuture, this.receiveStream, this.JS_ONLY_sendSink, this.client) {
    final subscription = listen((message) {
      if (message is ErrorReceived) {
        logger.warning('Error: ${message.error}', message.error, message.stackTrace);
      } else if (message is Disconnecting) {
        logger.info('Disconnecting: ${message.reason}');
      } else if (message is EventReceived) {
        final event = message.event;

        if (event is! RawDispatchEvent) {
          logger.finer('Receive: ${event.opcode.name}');

          switch (event) {
            case InvalidSessionEvent(:final isResumable):
              logger.finest('Resumable: $isResumable');
              if (isResumable) {
                logger.info('Reconnecting: invalid session');
              } else {
                logger.severe('Unresumable invalid session, disconnecting');
              }
            case HelloEvent(:final heartbeatInterval):
              logger.finest('Heartbeat Interval: $heartbeatInterval');
            case ReconnectEvent():
              logger.info('Reconnecting: reconnect requested');
            case HeartbeatAckEvent(:final latency):
              _latency = latency;
            default:
              break;
          }
        } else {
          logger
            ..fine('Receive event: ${event.name}')
            ..finer('Seq: ${event.seq}, Data: ${event.payload}');

          if (event.name == 'READY') {
            logger.info('Connected to Gateway');
          } else if (event.name == 'RESUMED') {
            logger.info('Reconnected to Gateway');
          }
        }
      }
    });

    subscription.asFuture().then((value) {
      // Can happen if the shard closes unexpectedly.
      // Prevents further calls to close() from attempting to add events.
      if (!_doneCompleter.isCompleted) {
        _doneCompleter.complete(value);
      }
    });
  }

  /// Connect to the Gateway using the provided parameters.
  static Future<Shard> connect(int id, int totalShards, GatewayApiOptions apiOptions, Uri connectionUri, NyxxGateway client) async {
    final logger = Logger('${client.options.loggerName}.Shards[$id]');

    logger.info('Connecting to Gateway');

    final sendSink = StreamController<dynamic>();
    final receiveStream = sendSink.stream.asBroadcastStream();

    final exitFuture = _isolateMain(_IsolateSpawnData(
      totalShards: totalShards,
      id: id,
      apiOptions: apiOptions,
      originalConnectionUri: connectionUri,
      sendSink: sendSink,
    ));

    exitFuture.then((_) {
      logger.info('Shard exited');

      sendSink.close();
    });

    final sendPort = await receiveStream.first as Sink<dynamic>;

    return Shard(id, exitFuture, receiveStream, sendPort, client);
  }

  /// Update the client's voice state on this shard.
  void updateVoiceState(Snowflake guildId, GatewayVoiceStateBuilder builder) {
    add(Send(opcode: Opcode.voiceStateUpdate, data: {
      'guild_id': guildId.toString(),
      ...builder.build(),
    }));
  }

  @override
  void add(GatewayMessage event) {
    if (event is Send) {
      logger
        ..fine('Send: ${event.opcode.name}')
        ..finer('Opcode: ${event.opcode.value}, Data: ${event.data}');
    } else if (event is Dispose) {
      logger.info('Disposing');
    }
    // ignore: deprecated_member_use_from_same_package
    JS_ONLY_sendSink.add(event);
  }

  @override
  StreamSubscription<ShardMessage> listen(
    void Function(ShardMessage event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return receiveStream.cast<ShardMessage>().listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  Future<void> close() {
    if (_doneCompleter.isCompleted) {
      return _doneCompleter.future;
    }

    Future<void> doClose() async {
      add(Dispose());

      // Wait for disconnection confirmation
      await firstWhere((message) => message is Disconnecting);

      // Give the isolate time to shut down cleanly, but kill it if it takes too long.
      try {
        await drain().timeout(const Duration(seconds: 5));
      } on TimeoutException {
        logger.warning('Isolate took too long to shut down, killing it');
        throw JsDisabledError('shard isolate killing');
      }
    }

    _doneCompleter.complete(doClose());
    return _doneCompleter.future;
  }

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  void addError(Object error, [StackTrace? stackTrace]) => throw UnimplementedError();

  @override
  Future<void> addStream(Stream<GatewayMessage> stream) => stream.forEach(add);
}

class _IsolateSpawnData extends ShardData {
  final Sink<dynamic> sendSink;

  _IsolateSpawnData({
    required super.totalShards,
    required super.id,
    required super.apiOptions,
    required super.originalConnectionUri,
    required this.sendSink,
  });
}

Future<void> _isolateMain(_IsolateSpawnData data) async {
  final sendSink = StreamController<dynamic>();
  data.sendSink.add(sendSink);

  final runner = ShardRunner(data);

  final subscription = runner.run(sendSink.stream.cast<GatewayMessage>()).listen(
    (message) {
      try {
        data.sendSink.add(message);
      } on ArgumentError {
        // The only message with anything custom should be ErrorReceived
        assert(message is ErrorReceived);
        message = message as ErrorReceived;
        data.sendSink.add(ErrorReceived(error: message.error.toString(), stackTrace: message.stackTrace));
      }
    },
    onDone: () => sendSink.close(),
  );

  return subscription.asFuture();
}
