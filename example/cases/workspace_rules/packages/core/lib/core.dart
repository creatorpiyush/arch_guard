import 'package:feature/feature.dart';

// core must not know about features.
String appName() => 'Shop ${featureCount()}';
