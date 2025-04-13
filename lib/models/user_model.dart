//user_model.dart
class UserModel {
  final String uid;
  final String email;
  final String name;
  final String photoUrl;
  final String fcmToken;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    this.photoUrl = '',
    this.fcmToken = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'photoUrl': photoUrl,
      'fcmToken': fcmToken,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
      fcmToken: map['fcmToken'] ?? '',
    );
  }
}
