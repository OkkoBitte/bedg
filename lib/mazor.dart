import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bedg/structs.dart' as structs;

const mazorCode = 1;

class PacketController {
  bool isActive = true;
  static const int maxLenghtManagment = 100;
  List<structs.MazorPacket> myPackets = [];
  final StreamController<structs.ActionControll> actions = StreamController<structs.ActionControll>();

  bool putMy(structs.MazorPacket packet) {
    for (final mpacket in myPackets.toList()) {
      if (mpacket.hxCode1 == packet.hxCode1 && mpacket.hxCode2 == packet.hxCode2) return true;
    }
    if (myPackets.length >= maxLenghtManagment) return false;
    myPackets.add(packet);
    actions.add(structs.ActionControll(structs.ActionControll.send, packet));
    return true;
  }

  bool putHe(structs.MazorPacket packet) {
    if (myPackets.length >= maxLenghtManagment) return false;
    
    if (packet.type == structs.PacketType.managment) {
      myPackets.removeWhere((p) => 
        p.hxCode1 == packet.hxCode1 && p.hxCode2 == packet.hxCode2);
    } 
    else if (packet.type == structs.PacketType.controll) {
      if (packet.data != null && packet.data!.isNotEmpty && 
          packet.data![0] == structs.PacketControll.close) {
        actions.add(structs.ActionControll(structs.ActionControll.close));
      }  
    } 
    else if (packet.type == structs.PacketType.data) {
      final ackPacket = structs.MazorPacket(
        type: structs.PacketType.managment,
        hxCode1: packet.hxCode1, 
        hxCode2: packet.hxCode2,
        timeOut: 0x10, 
        dataSize1: 0,
        dataSize2: 0, 
      );
      actions.add(structs.ActionControll(structs.ActionControll.send, ackPacket));
      actions.add(structs.ActionControll(structs.ActionControll.get, packet));
    }
    
    return true;
  } 

  Future<void> managment() async {
    while (isActive) {
      await Future.delayed(Duration(milliseconds: 100));
      
      if (actions.isClosed) {
        break;
      }
      for (final packet in myPackets.toList()) {
        if (packet.isExpired) {
          actions.add(structs.ActionControll(structs.ActionControll.send, packet));
          packet.restartTimer(); 
        }
      }

      actions.add(structs.ActionControll(
        structs.ActionControll.send,
        structs.MazorPacket(
          type: structs.PacketType.controll,
          hxCode1: 0,
          hxCode2: 0,
          timeOut: 0,
          dataSize1: 0,
          dataSize2: 1,

          data: Uint8List.fromList([structs.PacketControll.hier])

        )
        
      ));
    }
  }

  void stop() {
    isActive = false;
    actions.close();
  }
}
class ClientManager {
  StreamController<String> systemMessage = StreamController<String>(); 
  void Function()? onConnected;
  void Function(Uint8List data)? onGet;
  void Function()? onClose;
  void Function(String)? sMessage;
  structs.ClientHeadPacket clientTarget; 
  PacketController packetControll = PacketController();
  
  Socket? lPhisiceSocket;
  String lHostName;
  int lPort;
  bool isOfcConnect = false;
  
  ClientManager(this.clientTarget, this.lHostName, this.lPort, ) {
    packetControll.managment();
    packetControll.actions.stream.listen((action) {
      _handleAction(action);
    });
  }
  void addSmessage(String m){
    sMessage?.call(m);
    systemMessage.add(m);
  }
  void _handleAction(structs.ActionControll action) {
    switch (action.action) {
      case structs.ActionControll.send:
        if (action.packet != null) {
          final bytes = action.packet!.toBytes();
          lPhisiceSocket?.add(bytes);
        }
        break;
      case structs.ActionControll.get:
        onGet?.call(action.packet!.data!);
        break;
      case structs.ActionControll.close:
        disconnect();
        break;
    }
  }

  Future<bool> connect([String? hostName, int? port]) async {
    try {
      final targetHost = hostName ?? lHostName;
      final targetPort = port ?? lPort;
      
  
      
      if (isOfcConnect) {
        await lPhisiceSocket?.close();
      }

      lPhisiceSocket = await Socket.connect(
        targetHost, 
        targetPort, 
        timeout: const Duration(seconds: 10)
      );

      lPhisiceSocket?.add(clientTarget.toBytes());
      addSmessage(jsonEncode({
        'type': 'status',
        'head': 'connected',
        'message': 'Connected to $targetHost:$targetPort'
      }));
      
      onConnected?.call();
      reads();


      return true;
      
    } catch (e) {
      addSmessage(jsonEncode({
        'type': 'error',
        'head': 'disconnected',
        'message': 'Connection failed: $e'
      }));
     
      return false;
    }
  }

  Future<void> reads() async {
    if (lPhisiceSocket == null) return;
    
    lPhisiceSocket!.listen(
      (Uint8List data) {
        
        try {
          print("lenght ${data.length}");
          final packet = structs.MazorPacket.fromBytes(data);
          packetControll.putHe(packet);
        } catch (e) {
          addSmessage(jsonEncode({
            'type': 'error',
            'head': 'parse',
            'message': 'Failed to parse packet: $e'
          }));
        }
      },
      onError: (error) {
        addSmessage(jsonEncode({
          'type': 'error',
          'head': 'socket',
          'message': 'Socket error: $error'
        }));
      },
      onDone: () {
        addSmessage(jsonEncode({
          'type': 'status', 
          'head': 'disconnected',
          'message': 'Connection closed'
        }));
      },
      cancelOnError: true,
    );
  }

  Future<bool> send(Uint8List data, {int timeoutSeconds = 5}) async {
    try {
      if (lPhisiceSocket == null) {
        throw Exception('Not connected');
      }
      
      final random = Random();
      final dataSize = data.length;
      
      
      final packet = structs.MazorPacket(
        type: 3, 
        hxCode1: random.nextInt(256), 
        hxCode2: random.nextInt(256), 
        timeOut: 0x0A, 
        dataSize1: dataSize & 0xFF, 
        dataSize2: (dataSize >> 8) & 0xFF, 
        data: data,
      );
      
      while(!packetControll.putMy(packet)){  await Future.delayed(Duration(milliseconds: 100)); }

    
      
      
      return true;
    } catch (e) {
      addSmessage(jsonEncode({
        'type': 'error',
        'head': 'send',
        'message': 'Send failed: $e'
      }));
      return false;
    }
  }

  Future<void> disconnect() async {
    await lPhisiceSocket?.close();
    lPhisiceSocket = null;
    packetControll.stop();
    onConnected?.call();
  }

  void dispose() {
    disconnect();
    systemMessage.close();
  }
}