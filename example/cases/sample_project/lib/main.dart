import 'screens/home.dart';
import 'services/auth_service.dart';

void main() {
  final auth = AuthService();
  final home = HomeScreen();
  print('App initialized: $auth, $home');
}
