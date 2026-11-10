// ignore_for_file: depend_on_referenced_packages, uri_does_not_exist
import 'package:http/http.dart' as http;

class UserRepo {
  Future<void> load() => http.get(Uri.parse('https://example.com/user'));
}
