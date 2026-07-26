import 'package:sample_project/services/session_service.dart';

class User {
  final String id;
  final SessionService session;
  User(this.id, this.session);
}
