import 'user.dart';

abstract class UserRepository {
  Future<User> current();
}
