import '../application/auth_service.dart';
import '../presentation/widgets/error_banner.dart';

/// Left over from before the move to Riverpod.
class AuthBloc {
  final _service = AuthService();

  Future<void> signIn(String name) async {
    try {
      await _service.signIn(name);
    } catch (e) {
      ErrorBanner.show('$e');
    }
  }
}
