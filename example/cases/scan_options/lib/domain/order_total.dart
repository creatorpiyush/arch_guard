part of 'order.dart';

extension OrderTotal on Order {
  int get total => items.fold(0, (a, b) => a + b);
}
