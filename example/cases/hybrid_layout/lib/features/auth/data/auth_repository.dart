import '../domain/user.dart';

class AuthRepository {
  Future<User> signIn(String name) async => User(name);
}
