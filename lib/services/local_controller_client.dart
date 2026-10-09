import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/controller/nes_controller.dart';
import 'remote_protocol.dart';

/// Paired controller. Updates are sent immediately and signed keepalives every
/// 200 ms detect link loss so the host can release stuck buttons.
class LocalControllerClient {
  Socket? _socket;
  JsonLineBuffer? _buffer;
  Timer? _heartbeat;
  Completer<void>? _handshake;
  void Function(String)? _onStatus;
  void Function(Set<NesButton>)? _onButtons;
  String _code='';
  String? _hostNonce,_clientNonce,_sessionKey;
  int _sequence=0,_mask=0;
  bool _authenticated=false,_closing=false;
  bool get isConnected=>_authenticated;

  Future<void> connect({required String host,required String pairingCode,
    required void Function(Set<NesButton>) onButtonsChanged,
    required void Function(String) onStatusChanged,int port=47531}) async {
    await disconnect();
    final code=normalizedPairingCode(pairingCode);
    if(!isPairingCode(code)) { throw const FormatException('Enter the full 16-character pairing code.'); }
    _code=code;_onButtons=onButtonsChanged;_onStatus=onStatusChanged;_closing=false;
    _notify('Connecting to host');
    final socket=await Socket.connect(host.trim(),port,timeout:const Duration(seconds:8));
    _socket=socket;final handshake=Completer<void>();_handshake=handshake;
    _buffer=JsonLineBuffer(onLine:_handleLine,onInvalidFrame:()=>_fail(const FormatException('Invalid host frame')));
    socket.listen((data)=>_buffer?.add(data),onError:(Object _) => _closed(socket),
      onDone:()=>_closed(socket),cancelOnError:true);
    try {
      await handshake.future.timeout(const Duration(seconds:10));
      _heartbeat?.cancel();
      _heartbeat=Timer.periodic(const Duration(milliseconds:200),(_)=>_sendInput());
      _sendInput();
    } on Object {await disconnect();rethrow;}
  }

  void setButtons(Iterable<NesButton> buttons) {
    _mask=NesController.maskFor(buttons); if(_authenticated) { _sendInput(); }
  }

  Future<void> disconnect() async {
    _closing = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    final socket = _socket;
    if (socket != null && _authenticated) {
      // Send a final all-buttons-up frame and flush it before closing the
      // outgoing stream. Destroying immediately can drop the release frame.
      _mask = 0;
      _sendInput();
      try {
        await socket.flush();
      } on SocketException {
        // Continue with shutdown; the host watchdog still releases input.
      }
    }
    _authenticated = false;
    _socket = null;
    _buffer?.close();
    _buffer = null;
    _sessionKey = null;
    _hostNonce = null;
    _clientNonce = null;
    _mask = 0;
    if (socket != null) {
      try {
        await socket.close();
      } on SocketException {
        socket.destroy();
      }
    }
    _onButtons?.call(const <NesButton>{});
    _notify('Disconnected');
    _closing = false;
  }

  void _handleLine(String line) {
    try {
      final data=jsonDecode(line);
      if(data is! Map<String,dynamic>){_fail(const FormatException('Invalid host message'));return;}
      switch(data['type']) {
        case 'challenge':
          final nonce=data['nonce'];
          if(!isProtocolNonce(nonce)||_sessionKey!=null){_fail(const FormatException('Invalid host challenge'));return;}
          _hostNonce=nonce as String;_clientNonce=newProtocolNonce();
          _sessionKey=protocolMac(_code,'session|$_hostNonce|$_clientNonce');
          _send({'type':'auth','clientNonce':_clientNonce!,
            'proof':protocolMac(_code,'client|$_hostNonce|$_clientNonce')});
          break;
        case 'accepted':
          final hostNonce=_hostNonce,clientNonce=_clientNonce,key=_sessionKey,proof=data['proof'];
          if(hostNonce==null||clientNonce==null||key==null||!isHexSha256(proof)||
            !constantTimeEquals(proof as String,protocolMac(key,'server|$hostNonce|$clientNonce'))) {
            _fail(const FormatException('Host authentication failed'));return;
          }
          _authenticated=true;_sequence=0;_notify('Connected');
          final h=_handshake; if(h!=null&&!h.isCompleted) { h.complete(); }
          break;
        case 'error': _fail(StateError('Pairing rejected or host is busy'));break;
        default: _fail(const FormatException('Unknown host message'));
      }
    } on FormatException {_fail(const FormatException('Invalid host message'));}
    on TypeError {_fail(const FormatException('Invalid host message'));}
  }

  void _sendInput() {
    final key=_sessionKey; if(!_authenticated||key==null) { return; }
    final sequence=++_sequence,mask=_mask;
    _send({'type':'input','sequence':sequence,'mask':mask,'mac':protocolMac(key,'input|$sequence|$mask')});
  }
  void _send(Map<String,Object> data) {
    final socket=_socket; if(socket==null) { return; }
    try {socket.add(utf8.encode('${jsonEncode(data)}\n'));}
    on SocketException {_closed(socket);}
  }
  void _fail(Object error) {
    final h=_handshake; if(h!=null&&!h.isCompleted) { h.completeError(error); }
    final socket=_socket; if(socket!=null) { _closed(socket); }
  }
  void _closed(Socket socket) {
    if(!identical(socket,_socket)) { return; }
    _socket=null;_authenticated=false;_heartbeat?.cancel();_heartbeat=null;
    _buffer?.close();_buffer=null;_sessionKey=null;_mask=0;
    _onButtons?.call(const <NesButton>{});
    if(!_closing) { _notify('Host disconnected'); }
    final h=_handshake;
    if(h!=null&&!h.isCompleted) { h.completeError(const SocketException('Host disconnected during pairing.')); }
    socket.destroy();
  }
  void _notify(String value)=>_onStatus?.call(value);
}
