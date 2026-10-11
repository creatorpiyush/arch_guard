import '../data/auth_repository.dart';
import '../domain/user.dart';

class AuthService {
  final _repository = AuthRepository();

  Future<User> signIn(String name) => _repository.signIn(name);
}
