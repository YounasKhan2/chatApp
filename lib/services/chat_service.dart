import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<UserModel>> getUsers(String currentUserId) {
    return _firestore
        .collection('users')
        .where('uid', isNotEqualTo: currentUserId)
        .orderBy('uid')
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data()))
          .toList();
    });
  }

  Stream<List<UserModel>> getOnlineUsers() {
    return _firestore
        .collection('users')
        .where('isOnline', isEqualTo: true)
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data()))
          .toList();
    });
  }

  Stream<List<MessageModel>> getMessages(String senderId, String receiverId) {
    return _firestore
        .collection('messages')
        .where('senderId', whereIn: [senderId, receiverId])
        .where('receiverId', whereIn: [senderId, receiverId])
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data()))
          .toList();
    });
  }

  Future<void> sendMessage(MessageModel message) async {
    final messageData = {
      'id': message.id,
      'senderId': message.senderId,
      'receiverId': message.receiverId,
      'content': message.content,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'isSent': true,
    };

    await _firestore
        .collection('messages')
        .doc(message.id)
        .set(messageData);

    // Create notification for receiver
    await _firestore.collection('notifications').add({
      'userId': message.receiverId,
      'name': 'New Message',
      'body': message.content,
      'timestamp': FieldValue.serverTimestamp(),
      'data': {
        'senderId': message.senderId,
        'messageId': message.id,
      }
    });
  }

  Future<void> updateUserStatus(String userId, bool isOnline) async {
    await _firestore.collection('users').doc(userId).update({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }
}
