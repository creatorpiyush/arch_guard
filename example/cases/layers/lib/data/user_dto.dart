import '../domain/user.dart';

class UserDto {
  const UserDto(this.name);
  final String name;
  User toEntity() => User(name);
}
