import 'package:scan_options/data/order_row.dart';
import 'package:scan_options/domain/order.dart';

void main() {
  final Order order = OrderRow().toOrder();
  print(order.total);
}
