import '../domain/user.dart';
import '../domain/user_repository.dart';
import 'user_dto.dart';

class ApiUserRepository implements UserRepository {
  @override
  Future<User> current() async => const UserDto('Ada').toEntity();
}
