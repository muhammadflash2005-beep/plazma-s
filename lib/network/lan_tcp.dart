import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/frame_codec.dart';
import '../protocol/frame_stream_decoder.dart';

typedef PeerMessageHandler = FutureOr<void> Function(
  TcpPeer peer,
  Map<String, Object?> message,
);
typedef PeerEventHandler = FutureOr<void> Function(TcpPeer peer);

/// One framed JSON connection over a TCP socket.
class TcpPeer {
  TcpPeer._({
    required Socket socket,
    required FrameCodec codec,
    required PeerMessageHandler onMessage,
    PeerEventHandler? onDisconnected,
  })  : _socket = socket,
        _codec = codec,
        _decoder = FrameStreamDecoder(codec: codec),
        _onMessage = onMessage,
        _onDisconnected = onDisconnected {
    _subscription = socket.listen(
      _handleData,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final FrameCodec _codec;
  final FrameStreamDecoder _decoder;
  final PeerMessageHandler _onMessage;
  final PeerEventHandler? _onDisconnected;
  late final StreamSubscription<Uint8List> _subscription;
  bool _closed = false;

  String get address => _socket.remoteAddress.address;
  int get port => _socket.remotePort;
  bool get isClosed => _closed;

  static Future<TcpPeer> connect({
    required String host,
    required int port,
    required PeerMessageHandler onMessage,
    PeerEventHandler? onDisconnected,
    FrameCodec? codec,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    return TcpPeer._(
      socket: socket,
      codec: codec ?? FrameCodec(),
      onMessage: onMessage,
      onDisconnected: onDisconnected,
    );
  }

  Future<void> send(Map<String, Object?> message) async {
    if (_closed) throw StateError('Cannot send: TCP peer is closed.');
    _socket.add(_codec.encode(message));
    await _socket.flush();
  }

  void _handleData(Uint8List data) {
    try {
      for (final message in _decoder.add(data)) {
        unawaited(Future.sync(() => _onMessage(this, message)));
      }
    } catch (_) {
      unawaited(close());
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    unawaited(close());
  }

  void _handleDone() {
    unawaited(_finish());
  }

  Future<void> close() async {
    if (_closed) return;
    await _socket.close();
    await _finish();
  }

  Future<void> _finish() async {
    if (_closed) return;
    _closed = true;
    _decoder.reset();
    await _subscription.cancel();
    if (_onDisconnected != null) {
      await _onDisconnected(this);
    }
  }
}

/// TCP listener for receiving connections from devices on the same LAN.
class LanTcpServer {
  LanTcpServer({
    required this.onMessage,
    this.onPeerConnected,
    this.onPeerDisconnected,
    this.codec,
  });

  final PeerMessageHandler onMessage;
  final PeerEventHandler? onPeerConnected;
  final PeerEventHandler? onPeerDisconnected;
  final FrameCodec? codec;

  final Set<TcpPeer> _peers = {};
  ServerSocket? _server;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  InternetAddress? get address => _server?.address;
  List<TcpPeer> get peers => List.unmodifiable(_peers);

  Future<void> start({
    InternetAddress address = InternetAddress.anyIPv4,
    int port = 0,
  }) async {
    if (isRunning) throw StateError('TCP server is already running.');
    final server = await ServerSocket.bind(address, port);
    _server = server;
    server.listen(_accept, onError: (_) => close());
  }

  void _accept(Socket socket) {
    late final TcpPeer peer;
    peer = TcpPeer._(
      socket: socket,
      codec: codec ?? FrameCodec(),
      onMessage: onMessage,
      onDisconnected: (disconnectedPeer) async {
        _peers.remove(disconnectedPeer);
        if (onPeerDisconnected != null) {
          await onPeerDisconnected!(disconnectedPeer);
        }
      },
    );
    _peers.add(peer);
    if (onPeerConnected != null) {
      unawaited(Future.sync(() => onPeerConnected!(peer)));
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close();
    await Future.wait(_peers.toList().map((peer) => peer.close()));
    _peers.clear();
  }
}
