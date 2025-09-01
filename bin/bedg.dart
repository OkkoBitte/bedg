import 'dart:convert';
import 'dart:typed_data';
import 'package:bedg/mazor.dart';
import 'package:bedg/structs.dart';

void main(List<String> arguments) async {
  await Future.delayed(Duration(milliseconds: 100));
  String sey = generateRandomString(20);
  print("My sey: $sey");
  final chp = ClientHeadPacket(
    clientSey: sey,
    clientOptions: Uint8List.fromList([0x01, 0x02, 0xFF, 0, 0, 0, 0, 0, 0, mazorCode]),
  );
  
  final cm = ClientManager(chp, "web-mbg.ru", 333);

  final connected = await cm.connect();
  if (!connected) {
    print("Connection failed!");
    return;
  }
  cm.onConnected = (){
    print("Connected");
  };
  cm.onGet = (data) {
  
    print("Get-> ${String.fromCharCodes(data)}");
  };
  cm.onClose = (){
    print("Close");
  };
  cm.sMessage = (m){
    print(m);
  };
  
  cm.send(Uint8List.fromList(
    utf8.encode(sey) // who? (my)
    +
    [1] // type text
    +
    utf8.encode("hello") // message
    ));

  await Future.delayed(Duration(seconds: 20));
  cm.disconnect();
}