import 'dart:mirrors';

class Serializer {
  String nameOf(Object o) => MirrorSystem.getName(reflect(o).type.simpleName);
}
