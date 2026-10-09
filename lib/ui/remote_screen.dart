import 'package:flutter/material.dart';
import '../core/controller/nes_controller.dart';
import '../services/local_controller_client.dart';
import '../services/local_controller_server.dart';

enum RemoteMode { host, controller }

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({required this.mode,required this.hostController,super.key});
  final RemoteMode mode;
  final NesController hostController;
  @override State<RemoteScreen> createState()=>_RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  late final LocalControllerServer _server;
  late final LocalControllerClient _client;
  final _hostInput=TextEditingController(),_codeInput=TextEditingController();
  final Set<NesButton> _pressed=<NesButton>{};
  String _status = 'Not connected';
  String? _pairCode;
  List<String> _addresses=const <String>[];
  bool _busy=false;

  @override void initState() {
    super.initState();
    _server=LocalControllerServer(
      onButtonsChanged:widget.hostController.setButtons,
      onStatusChanged:(s){if(mounted)setState(()=>_status=s);},
    );
    _client=LocalControllerClient();
  }
  @override void dispose() {
    _server.stop();_client.disconnect();_hostInput.dispose();_codeInput.dispose();super.dispose();
  }
  Future<void> _startHost() async {
    setState(()=>_busy=true);
    try {
      await _server.start();
      if(!mounted)return;
      setState((){_pairCode=_server.pairingCode;_addresses=_server.addresses;});
    } on Object catch(e) {if(mounted)_error(e.toString());}
    finally {if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _stopHost() async {
    await _server.stop();if(!mounted)return;
    setState((){_pairCode=null;_addresses=const <String>[];});
  }
  Future<void> _connect() async {
    setState(()=>_busy=true);
    try {
      await _client.connect(host:_hostInput.text,pairingCode:_codeInput.text,
        onButtonsChanged:(_){},onStatusChanged:(s){if(mounted)setState(()=>_status=s);});
      if(mounted)setState((){});
    } on Object catch(e) {if(mounted)_error(e.toString());}
    finally {if(mounted)setState(()=>_busy=false);}
  }
  void _setButton(NesButton button,bool down) {
    if(down){_pressed.add(button);}else{_pressed.remove(button);}
    _client.setButtons(_pressed);setState((){});
  }
  void _error(String message)=>ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(message),backgroundColor:Colors.red.shade900));

  @override Widget build(BuildContext context) {
    final host=widget.mode==RemoteMode.host;
    return Scaffold(backgroundColor:Colors.black,
      appBar:AppBar(backgroundColor:Colors.black,foregroundColor:Colors.white,
        title:Text(host?'Host emulator':'Wi-Fi controller')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:<Widget>[
        Text(_status,style:const TextStyle(color:Colors.white,fontSize:16)),
        const SizedBox(height:20),
        if(host) ..._hostControls() else ..._controllerControls(),
        const SizedBox(height:24),
        const Divider(color:Colors.white24),
        const Text('Both devices must be on the same local Wi-Fi network. No account or internet service is used. Input frames are authenticated, but transport encryption is not enabled; use a trusted LAN.',
          style:TextStyle(color:Colors.white70,height:1.45)),
      ])));
  }

  List<Widget> _hostControls()=> <Widget>[
    if(_pairCode==null)
      FilledButton(onPressed:_busy?null:_startHost,style:_primary(),child:const Text('Start local controller host'))
    else ...<Widget>[
      const Text('Enter this pairing code on the second device',style:TextStyle(color:Colors.white70)),
      const SizedBox(height:8),
      SelectableText(_pairCode!,style:const TextStyle(color:Colors.white,fontSize:25,letterSpacing:2,fontWeight:FontWeight.bold)),
      const SizedBox(height:14),
      const Text('Host IPv4 address and port',style:TextStyle(color:Colors.white70)),
      for(final ip in _addresses) SelectableText('$ip:${_server.boundPort}',style:const TextStyle(color:Colors.white,fontSize:18)),
      if(_addresses.isEmpty) const Text('No local address detected. Connect to Wi-Fi and restart the host.',style:TextStyle(color:Colors.white70)),
      const SizedBox(height:14),
      OutlinedButton(onPressed:_stopHost,style:_outline(),child:const Text('Stop host and release buttons')),
    ],
  ];

  List<Widget> _controllerControls()=> <Widget>[
    TextField(controller:_hostInput,keyboardType:TextInputType.number,style:const TextStyle(color:Colors.white),
      decoration:_input('Host IPv4 address')),
    const SizedBox(height:12),
    TextField(controller:_codeInput,textCapitalization:TextCapitalization.characters,autocorrect:false,
      style:const TextStyle(color:Colors.white,letterSpacing:1.4),decoration:_input('16-character pairing code')),
    const SizedBox(height:12),
    FilledButton(onPressed:_busy||_client.isConnected?null:_connect,style:_primary(),child:const Text('Connect')),
    if(_client.isConnected) ...<Widget>[
      const SizedBox(height:20),
      const Text('Hold buttons. Multi-touch supports simultaneous input.',style:TextStyle(color:Colors.white70)),
      const SizedBox(height:16),
      Center(child:Column(children:<Widget>[
        _touch('UP',NesButton.up),
        Row(mainAxisSize:MainAxisSize.min,children:<Widget>[
          _touch('LEFT',NesButton.left),const SizedBox(width:10),
          _touch('DOWN',NesButton.down),const SizedBox(width:10),
          _touch('RIGHT',NesButton.right),
        ]),
      ])),
      const SizedBox(height:20),
      Wrap(alignment:WrapAlignment.center,spacing:10,runSpacing:10,children:<Widget>[
        _touch('B',NesButton.b),_touch('A',NesButton.a),
        _touch('SELECT',NesButton.select),_touch('START',NesButton.start),
      ]),
      const SizedBox(height:16),
      OutlinedButton(onPressed:() async {await _client.disconnect();if(mounted)setState(()=>_pressed.clear());},
        style:_outline(),child:const Text('Disconnect and release buttons')),
    ],
  ];

  Widget _touch(String label,NesButton button) {
    final active=_pressed.contains(button);
    return GestureDetector(onTapDown:(_)=>_setButton(button,true),
      onTapUp:(_)=>_setButton(button,false),onTapCancel:()=>_setButton(button,false),
      child:AnimatedContainer(duration:const Duration(milliseconds:60),width:label.length>5?94:70,height:58,
        alignment:Alignment.center,decoration:BoxDecoration(
          color:active?Colors.white:Colors.black,border:Border.all(color:Colors.white,width:1.5),
          borderRadius:BorderRadius.circular(10)),
        child:Text(label,style:TextStyle(color:active?Colors.black:Colors.white,fontWeight:FontWeight.bold))));
  }
  InputDecoration _input(String hint)=>InputDecoration(hintText:hint,hintStyle:const TextStyle(color:Colors.white54),
    enabledBorder:const OutlineInputBorder(borderSide:BorderSide(color:Colors.white54)),
    focusedBorder:const OutlineInputBorder(borderSide:BorderSide(color:Colors.white)));
  ButtonStyle _primary()=>FilledButton.styleFrom(backgroundColor:Colors.white,foregroundColor:Colors.black,minimumSize:const Size.fromHeight(48));
  ButtonStyle _outline()=>OutlinedButton.styleFrom(foregroundColor:Colors.white,side:const BorderSide(color:Colors.white54),minimumSize:const Size.fromHeight(48));
}
