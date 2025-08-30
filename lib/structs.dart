import 'dart:typed_data';

class ClientHeadPacket {
  
  final Uint8List clientOptions; // 10 bytes
  final String clientSey;        // 20 chars max
  
  ClientHeadPacket({
    Uint8List? clientOptions,
    required this.clientSey,
  }) : clientOptions = clientOptions ?? Uint8List(10) {
    if (this.clientOptions.length != 10) {
      throw ArgumentError('clientOptions must be exactly 10 bytes');
    }
    if (clientSey.length != 20) {
      throw ArgumentError('clientSey must be max 20 characters');
    }
  }
  
  
  Uint8List toBytes() {
    final bytes = Uint8List(30); // 10 + 20
    bytes.setRange(0, 10, clientOptions);
    

    final seyBytes = clientSey.codeUnits;
    bytes.setRange(10, 10 + seyBytes.length, seyBytes);
    
    for (int i = 10 + seyBytes.length; i < 30; i++) {
      bytes[i] = 0;
    }
    
    return bytes;
  }
  

  factory ClientHeadPacket.fromBytes(Uint8List data) {
    if (data.length < 30) {
      throw ArgumentError('Data must be at least 30 bytes');
    }
    
    final options = data.sublist(0, 10);
    
    int seyEnd = 10;
    while (seyEnd < 30 && data[seyEnd] != 0) {
      seyEnd++;
    }
    
    final seyBytes = data.sublist(10, seyEnd);
    final seyString = String.fromCharCodes(seyBytes);
    
    return ClientHeadPacket(
      clientOptions: options,
      clientSey: seyString,
    );
  }
}

class MazorPacket {
  static const int headerSize = 6;
  final DateTime timeCreate;
  final Stopwatch _lifeTimer; 

  int type;
  int hxCode1;
  int hxCode2;
  int timeOut;
  int dataSize1;
  int dataSize2;
  Uint8List? data; 

  MazorPacket({
    required this.type,
    required this.hxCode1,
    required this.hxCode2,  
    required this.timeOut,
    required this.dataSize1,
    required this.dataSize2,
    this.data,
  }) : timeCreate = DateTime.now(),
        _lifeTimer = Stopwatch()..start() {
    _validateByte('type', type);
    _validateByte('hxCode1', hxCode1);
    _validateByte('hxCode2', hxCode2);
    _validateByte('timeOut', timeOut);
    _validateByte('dataSize1', dataSize1);
    _validateByte('dataSize2', dataSize2);
  }

  void _validateByte(String name, int value) {
    if (value < 0 || value > 255) {
      throw ArgumentError('$name must be between 0 and 255, got $value');
    }
  }

  Uint8List getHeadUint() {
    return Uint8List.fromList([
      type,
      hxCode1,
      hxCode2,
      timeOut,
      dataSize1,
      dataSize2,
    ]);
  }

  Uint8List toBytes() {
    final header = getHeadUint();
    final dataBytes = data ?? Uint8List(0); 
    final result = Uint8List(headerSize + dataBytes.length);
    result.setRange(0, headerSize, header);
    result.setRange(headerSize, result.length, dataBytes);
    return result;
  }

  factory MazorPacket.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw ArgumentError('Packet too short');
    }

    return MazorPacket(
      type: bytes[0],
      hxCode1: bytes[1],
      hxCode2: bytes[2],
      timeOut: bytes[3],
      dataSize1: bytes[4],
      dataSize2: bytes[5],
      data: bytes.length > headerSize ? bytes.sublist(headerSize) : null,
    );
  }


  bool get hasData => data != null && data!.isNotEmpty;
  
 
  int get dataLength => data?.length ?? 0;
  

  int get totalSize => headerSize + dataLength;

  Duration get lifeTime => _lifeTimer.elapsed;
  
  void restartTimer() => _lifeTimer.reset();
  
  void stopTimer() => _lifeTimer.stop();
  
  void startTimer() => _lifeTimer.start();
  
  bool get isExpired => lifeTime.inSeconds > timeOut;
  
  String get timerInfo => 'LifeTime: ${lifeTime.inMilliseconds}ms, Expired: $isExpired';
  
 
  @override
  String toString() {
    return 'MazorPacket[type: $type, data: ${hasData ? "$dataLength bytes" : "none"}, age: ${lifeTime.inMilliseconds}ms]';
  }
}

class ActionControll{
  
  static const String send = "send";
  static const String get  = "get";
  static const String close = "close";

  String action;

  /*🤔*/MazorPacket? packet; 

  ActionControll(this.action, [this.packet]);

}

class PacketType{
  static const int managment = 0x01;
  static const int controll = 0x02;
  static const int data = 0x03;
}

class PacketControll{
  static const int hier = 0xA0;
  static const int close = 0xFF;

}