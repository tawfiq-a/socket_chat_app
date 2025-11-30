import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:uuid/uuid.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  late IO.Socket socket;
  final TextEditingController controller = TextEditingController();
  final List<Map<String, dynamic>> messages = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  bool isTyping = false;

  final ImagePicker _picker = ImagePicker();
  final String clientId = Uuid().v4(); // unique user ID

  @override
  void initState() {
    super.initState();
    connectSocket();
  }

  // ------------------------ SOCKET CONNECT ----------------------------
  void connectSocket() {
    socket = IO.io("http://10.0.80.7:3000", <String, dynamic>{
      "transports": ["websocket"],
      "autoConnect": true,
    });

    socket.onConnect((_) => print("CONNECTED ✔"));

    // -------------------- RECEIVE TEXT --------------------
    socket.on("receiveMessage", (data) {
      final msg = Map<String, dynamic>.from(data);

      // ignore own msg
      if (msg["clientId"] == clientId) return;

      messages.add({
        "type": "text",
        "msg": msg["msg"],
        "isMe": false,
        "time": DateTime.now(),
      });

      _listKey.currentState?.insertItem(messages.length - 1);
      setState(() => isTyping = false);
    });

    // -------------------- RECEIVE IMAGE --------------------
    socket.on("receiveImage", (data) {
      final msg = Map<String, dynamic>.from(data);

      if (msg["clientId"] == clientId) return;

      messages.add({
        "type": "image",
        "msg": msg["msg"],
        "isMe": false,
        "time": DateTime.now(),
      });

      _listKey.currentState?.insertItem(messages.length - 1);
    });

    // -------------------- TYPING --------------------
    socket.on("typing", (data) {
      if (data['clientId'] != clientId) {
        setState(() => isTyping = true);
      }
    });

    socket.on("stopTyping", (data) {
      if (data['clientId'] != clientId) {
        setState(() => isTyping = false);
      }
    });
  }

  // ----------------------- SEND TEXT ------------------------
  void sendMessage() {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final msgData = {"msg": text, "clientId": clientId};

    messages.add({
      "type": "text",
      "msg": text,
      "isMe": true,
      "time": DateTime.now(),
    });

    _listKey.currentState?.insertItem(messages.length - 1);

    socket.emit("sendMessage", msgData);
    socket.emit("stopTyping");
    controller.clear();
  }

  // ----------------------- SEND IMAGE ------------------------
  Future<void> sendImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final imgData = {"msg": base64Image, "clientId": clientId};

    messages.add({
      "type": "image",
      "msg": base64Image,
      "isMe": true,
      "time": DateTime.now(),
    });

    _listKey.currentState?.insertItem(messages.length - 1);

    socket.emit("sendImage", imgData);
  }

  // ---------------------------- TYPING ----------------------------
  void onTyping(String text) {
    if (text.isNotEmpty) {
      socket.emit("typing", {"clientId": clientId});
    } else {
      socket.emit("stopTyping", {"clientId": clientId});
    }
  }

  // ---------------------------- TIME FORMAT ----------------------------
  String formatTime(DateTime t) {
    return "${t.hour}:${t.minute.toString().padLeft(2, '0')}";
  }

  // ---------------------------- UI ----------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Chat App"),
            // if (isTyping)
            //   Text("typing…",
            //       style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),

      body: Column(
        children: [
          Expanded(
            child: AnimatedList(
              key: _listKey,
              initialItemCount: messages.length,
              padding: EdgeInsets.all(12),
              itemBuilder: (context, index, animation) {
                final message = messages[index];
                bool isMe = message["isMe"];
                String type = message["type"];
                String msg = message["msg"];
                DateTime time = message["time"];

                Widget content;

                if (type == "text") {
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        msg,
                        style: TextStyle(
                          fontSize: 16,
                          color: isMe ? Colors.white : Colors.black,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        formatTime(time),
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ],
                  );
                } else {
                  final bytes = base64Decode(msg);
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Image.memory(Uint8List.fromList(bytes), width: 150),
                      SizedBox(height: 5),
                      Text(
                        formatTime(time),
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ],
                  );
                }

                return SizeTransition(
                  sizeFactor: animation,
                  child: Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 5),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.blue : Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                          bottomLeft: isMe
                              ? Radius.circular(12)
                              : Radius.circular(0),
                          bottomRight: isMe
                              ? Radius.circular(0)
                              : Radius.circular(12),
                        ),
                      ),
                      child: content,
                    ),
                  ),
                );
              },
            ),
          ),

          // ---------- TYPING INDICATOR (Below the message list) ----------
          if (isTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    height: 12,
                    width: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text("Typing...", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),

          // ------------------------- INPUT BOX -------------------------
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.image, size: 28),
                  onPressed: sendImage,
                ),

                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onTyping,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: "Type a message…",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                  ),
                ),

                SizedBox(width: 10),

                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
