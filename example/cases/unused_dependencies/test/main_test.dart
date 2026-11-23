import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Fake extends Mock {}

void main() => test('fake', () => _Fake());
