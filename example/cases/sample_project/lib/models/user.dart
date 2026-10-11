import '../services/session_service.dart';
import 'dart:convert';

class User {
  final String id;
  final SessionService session;
  User(this.id, this.session);

  String toJson() => jsonEncode({'id': id});
}
