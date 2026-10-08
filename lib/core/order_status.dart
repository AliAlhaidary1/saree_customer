import 'json_util.dart';

/// Parity with front `src/utils/orderDisplayStatus.js` + Order.jsx / OrderDetails.jsx
/// mapping logic. Single source of truth for mobile order display.

// Legacy numeric statuses (front Order.jsx getImageofOrderStatus / getStatus)
const int stPaymentPending = 1;
const int stConfirmed = 2;
const int stPreparing = 3;
const int stShipped = 4;
const int stOutForDelivery = 5;
const int stDelivered = 6;
const int stCancelled = 7;
const int stReturned = 8;

/// Checkout-group customer_status values considered terminal (front Order.jsx).
const terminalCheckoutStatuses = ['delivered', 'cancelled'];

/// Front Order.jsx / OrderDetails.jsx statusMap: customer_status -> legacy active_status string.
String mapGroupStatusToLegacy(dynamic customerStatus) {
  const map = {
    'awaiting_payment': '2',
    'confirmed': '2',
    'preparing': '3',
    'ready': '3',
    'in_delivery': '3',
    'out_for_delivery': '5',
    'delivered': '6',
    'cancelled': '7',
  };
  return map['$customerStatus'] ?? '2';
}

String itemStatusFromSellerOrder(Map<String, dynamic> item, Map<String, dynamic> so) {
  if (J.str(item['return_status']) == 'completed') return '8';
  if (J.str(so['fulfillment_status']) == 'cancelled') return '7';
  if (J.str(so['delivery_status']) == 'delivered') return '6';
  final ds = J.str(so['delivery_status']);
  if (ds == 'out_for_delivery' || ds == 'picked_up') return '5';
  final fs = J.str(so['fulfillment_status']);
  if (fs == 'preparing' || fs == 'ready') return '3';
  return '2';
}

class DisplayStatus {
  final String key;
  final String tone;
  const DisplayStatus(this.key, this.tone);
}

DisplayStatus storeDisplayFromGroupStatus(dynamic status) {
  final s = '$status'.toLowerCase();
  if (s == 'awaiting_payment') return const DisplayStatus('paymentPending', 'warn');
  if (s == 'delivered') return const DisplayStatus('delivered', 'ok');
  if (s == 'cancelled') return const DisplayStatus('cancelled', 'bad');
  if (s == 'refunded' || s == 'returned') return const DisplayStatus('returned', 'warn');
  if (s == 'out_for_delivery' || s == 'picked_up') return const DisplayStatus('on_the_way', 'alert');
  return const DisplayStatus('preparing_status', 'info');
}

DisplayStatus storeDisplayFromLegacy(dynamic activeStatus) {
  final n = J.i(activeStatus);
  if (n == 1) return const DisplayStatus('paymentPending', 'warn');
  if (n == 6) return const DisplayStatus('delivered', 'ok');
  if (n == 7) return const DisplayStatus('cancelled', 'bad');
  if (n == 8) return const DisplayStatus('returned', 'warn');
  if (n == 5) return const DisplayStatus('on_the_way', 'alert');
  return const DisplayStatus('preparing_status', 'info');
}

/// Front OrderDetails STEPS ids: [2 confirmed, 3 preparing, 5 on_the_way, 6 delivered]
int stepIndexForActive(dynamic activeStatus) {
  final n = J.i(activeStatus);
  const steps = [2, 3, 5, 6];
  return steps.indexOf(n);
}

double progressForActive(dynamic activeStatus) {
  final n = J.i(activeStatus);
  if (n >= 6 && n != 7 && n != 8) return 100;
  final idx = stepIndexForActive(activeStatus);
  if (idx <= 0) return 12;
  return (idx / 3) * 100;
}

/// Parity with front `mapCheckoutGroupToOrder` (OrderDetails.jsx:93-148).
Map<String, dynamic> mapCheckoutGroupToOrder(Map<String, dynamic> cg) {
  final sellerOrders = J.maps(cg['seller_orders'] ?? cg['orders']);
  final items = <Map<String, dynamic>>[];
  for (final so in sellerOrders) {
    for (final item in J.maps(so['items'])) {
      final merged = Map<String, dynamic>.from(item);
      merged['name'] = item['name'] ?? item['product_name'];
      merged['seller_id'] = so['seller_id'];
      merged['seller_name'] = so['store_name'];
      merged['active_status'] = itemStatusFromSellerOrder(item, so);
      merged['seller'] = {
        'latitude': so['seller_latitude'],
        'longitude': so['seller_longitude'],
      };
      items.add(merged);
    }
  }
  final snapRaw = cg['address_snapshot'];
  final snap = snapRaw is Map ? J.map(snapRaw) : <String, dynamic>{};
  final shortFromSnap = snap.isNotEmpty
      ? [J.str(snap['address']), J.str(snap['area']), J.str(snap['city'])]
          .where((e) => e.isNotEmpty)
          .join('، ')
      : '';
  final out = Map<String, dynamic>.from(cg);
  out['order_id'] = cg['id'];
  out['public_id'] = cg['public_id'] ?? cg['id'];
  out['is_checkout_group'] = true;
  out['items'] = items;
  out['order_items'] = items;
  out['active_status'] = mapGroupStatusToLegacy(cg['customer_status']);
  out['total'] = cg['subtotal'] ?? cg['total'];
  out['delivery_charge'] = cg['delivery_total'] ?? cg['delivery_charge'];
  out['wallet_balance'] = cg['wallet_applied'] ?? cg['wallet_balance'];
  out['final_total'] = cg['final_total'];
  out['address_snapshot'] = snap;
  out['order_address'] = shortFromSnap.isNotEmpty
      ? shortFromSnap
      : (J.str(snap['formatted']).isNotEmpty
          ? J.str(snap['formatted'])
          : [J.str(snap['address']), J.str(snap['area']), J.str(snap['city'])]
              .where((e) => e.isNotEmpty)
              .join('، '));
  out['mobile'] = J.str(cg['mobile']).isNotEmpty
      ? J.str(cg['mobile'])
      : J.str(snap['mobile']).isNotEmpty
          ? J.str(snap['mobile'])
          : J.str(snap['phone']);
  return out;
}

/// Parity with front `mergeOrders` (Order.jsx:80-88): merge legacy + groups,
/// filter by terminal for active/previous tab, sort by created_at desc.
List<Map<String, dynamic>> mergeOrders(
  List<Map<String, dynamic>> legacy,
  List<Map<String, dynamic>> checkoutGroups,
  bool active,
) {
  final mapped = checkoutGroups.map(mapCheckoutGroupToOrder).where((o) {
    final cs = J.str(o['customer_status']);
    final isTerminal = terminalCheckoutStatuses.contains(cs);
    return active ? !isTerminal : isTerminal;
  }).toList();
  final combined = [...mapped, ...legacy];
  combined.sort((a, b) {
    final da = DateTime.tryParse(J.str(a['created_at']));
    final db = DateTime.tryParse(J.str(b['created_at']));
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return combined;
}

/// Extract rows + total from either paginated map {data:{data,total}} or flat list.
/// Mirrors front: checkoutPayload?.data?.data || checkoutPayload?.data
({List<Map<String, dynamic>> rows, int total}) parseCheckoutGroupsPayload(ApiResult res) {
  final raw = res.raw;
  final data = raw['data'];
  if (data is Map) {
    final inner = data['data'];
    if (inner is List) {
      return (rows: J.maps(inner), total: J.i(data['total']));
    }
    return (rows: J.maps(data['data'] ?? data), total: J.i(data['total'] ?? raw['total']));
  }
  return (rows: res.dataMaps, total: J.i(raw['total']));
}

({List<Map<String, dynamic>> rows, int total}) parseOrdersPayload(ApiResult res) {
  final raw = res.raw;
  final data = raw['data'];
  if (data is Map && data['data'] is List) {
    return (rows: J.maps(data['data']), total: J.i(data['total'] ?? raw['total']));
  }
  return (rows: res.dataMaps, total: J.i(raw['total'] ?? res.dataMap['total']));
}
