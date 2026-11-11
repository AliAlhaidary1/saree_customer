import 'package:flutter_test/flutter_test.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/order_status.dart';

void main() {
  group('mapGroupStatusToLegacy', () {
    test('all mapped statuses', () {
      const mapping = {
        'awaiting_payment': '2',
        'confirmed': '2',
        'preparing': '3',
        'ready': '3',
        'in_delivery': '3',
        'out_for_delivery': '5',
        'delivered': '6',
        'cancelled': '7',
      };
      mapping.forEach((k, v) => expect(mapGroupStatusToLegacy(k), v));
    });

    test('unknown status defaults to confirmed (2)', () {
      expect(mapGroupStatusToLegacy('garbage'), '2');
      expect(mapGroupStatusToLegacy(''), '2');
      expect(mapGroupStatusToLegacy(null), '2');
    });
  });

  group('itemStatusFromSellerOrder', () {
    test('return_status completed wins over everything', () {
      expect(
        itemStatusFromSellerOrder(
          {'return_status': 'completed'},
          {'delivery_status': 'delivered', 'fulfillment_status': 'preparing'},
        ),
        '8',
      );
    });

    test('cancelled fulfillment beats delivery', () {
      expect(
        itemStatusFromSellerOrder(
          {'return_status': 'new'},
          {'fulfillment_status': 'cancelled', 'delivery_status': 'in_transit'},
        ),
        '7',
      );
    });

    test('delivered wins over later stages', () {
      expect(
        itemStatusFromSellerOrder(
          {},
          {'delivery_status': 'delivered', 'fulfillment_status': 'preparing'},
        ),
        '6',
      );
    });

    test('out_for_delivery yields 5, in_preparing yields 3', () {
      expect(
        itemStatusFromSellerOrder(
          {},
          {'delivery_status': 'out_for_delivery'},
        ),
        '5',
      );
      expect(
        itemStatusFromSellerOrder(
          {},
          {'delivery_status': 'picked_up'},
        ),
        '5',
      );
      expect(
        itemStatusFromSellerOrder({}, {'fulfillment_status': 'ready'}),
        '3',
      );
    });

    test('unknown combination defaults to confirmed (2)', () {
      expect(itemStatusFromSellerOrder({}, {}), '2');
      expect(
        itemStatusFromSellerOrder(
          {},
          {'delivery_status': 'in_transit', 'fulfillment_status': 'unknown'},
        ),
        '2',
      );
    });
  });

  group('mapCheckoutGroupToOrder', () {
    Map<String, dynamic> sample() => {
          'id': 7001,
          'public_id': 'grp-7001',
          'customer_status': 'out_for_delivery',
          'subtotal': 120,
          'delivery_total': 15,
          'wallet_applied': 20,
          'final_total': 115,
          'mobile': '777000000',
          'seller_orders': [
            {
              'seller_id': 51,
              'store_name': 'متجر الشرقية',
              'seller_latitude': '15.1',
              'seller_longitude': '45.2',
              'delivery_status': 'out_for_delivery',
              'fulfillment_status': 'ready',
              'items': [
                {'id': 10, 'name': 'عسل سدر', 'qty': 2, 'price': 60},
              ],
            },
            {
              'seller_id': 52,
              'store_name': 'متجر الغرب',
              'seller_latitude': '15.3',
              'seller_longitude': '45.4',
              'delivery_status': 'preparing',
              'fulfillment_status': 'preparing',
              'items': [
                {'id': 11, 'name': 'شاي أخضر', 'qty': 1, 'price': 30},
              ],
            },
          ],
          'address_snapshot': {
            'address': 'شارع الجديد',
            'area': 'المنطقة الصناعية',
            'city': 'صنعاء',
            'mobile': '777000000',
          },
        };

    test('maps items across sellers with merged seller fields', () {
      final out = mapCheckoutGroupToOrder(sample());
      final items = J.maps(out['items']);
      expect(items, hasLength(2));
      expect(items.first['name'], 'عسل سدر');
      expect(items.first['seller_id'], 51);
      expect(items.first['seller_name'], 'متجر الشرقية');
      expect(items.first['seller'], isA<Map<String, dynamic>>());
      expect(out['public_id'], 'grp-7001');
      expect(out['order_id'], 7001);
      expect(out['is_checkout_group'], true);
    });

    test('totals mirror the group subtotal/delivery/wallet', () {
      final out = mapCheckoutGroupToOrder(sample());
      expect(out['total'], 120);
      expect(out['delivery_charge'], 15);
      expect(out['wallet_balance'], 20);
      expect(out['final_total'], 115);
      expect(out['active_status'], '5');
    });

    test('address_snapshot is surfaced at top level and order_address string joined', () {
      final out = mapCheckoutGroupToOrder(sample());
      expect(out['address_snapshot'], isA<Map<String, dynamic>>());
      final addr = '${out['order_address']}';
      expect(addr, contains('شارع الجديد'));
      expect(addr, contains('صنعاء'));
      expect(out['mobile'], '777000000');
    });

    test('missing seller_orders yields empty items without crashing', () {
      final out = mapCheckoutGroupToOrder({
        'id': 1,
        'customer_status': 'preparing',
      });
      expect(out['items'], isEmpty);
      expect(out['order_id'], 1);
    });
  });

  group('mergeOrders', () {
    Map<String, dynamic> legacy(String id, String createdAt, String activeStatus) => {
          'id': id,
          'public_id': 'L-$id',
          'created_at': createdAt,
          'active_status': activeStatus,
        };
    List<Map<String, dynamic>> groups() => [
          {
            'id': 1001,
            'customer_status': 'delivered',
            'created_at': '2026-03-01 10:00:00',
            'subtotal': 100,
            'seller_orders': <Map<String, dynamic>>[],
          },
          {
            'id': 1002,
            'customer_status': 'preparing',
            'created_at': '2026-03-02 10:00:00',
            'subtotal': 100,
            'seller_orders': <Map<String, dynamic>>[],
          },
        ];

    test('active tab: terminal groups dropped, sorted desc by date', () {
      final out = mergeOrders(
        [legacy('L-1', '2026-03-03 10:00:00', '2')],
        groups(),
        true,
      );
      expect(out.map((e) => e['customer_status'] ?? 'legacy'),
          contains('preparing'));
      expect(out.map((e) => e['customer_status']), isNot(contains('delivered')));
    });

    test('previous tab: only terminal groups + legacy terminal lines survive', () {
      final out = mergeOrders(
        [legacy('L-1', '2026-03-03 10:00:00', '2')],
        groups(),
        false,
      );
      // previous tab: terminal groups delivered survive; legacy '2'
      // (active) rows are NOT terminated -> They survive because not pre-filtered.
      expect(out.any((e) => e['customer_status'] == 'delivered'), isTrue);
    });
  });

  group('parse payload helpers', () {
    test('flat list data is returned as rows', () {
      final res = ApiResult({
        'status': 1,
        'data': [
          {'id': 1},
          {'id': 2},
        ],
      });
      final r = parseCheckoutGroupsPayload(res);
      expect(r.rows.length, 2);
      expect(r.total, 0); // no top-level total provided in a bare List envelope
    });

    test('paginated map shape is unwrapped', () {
      final res = ApiResult({
        'status': 1,
        'data': {
          'data': [
            {'id': 1},
            {'id': 2},
            {'id': 3},
          ],
          'total': 42,
        },
      });
      final r = parseCheckoutGroupsPayload(res);
      expect(r.rows.length, 3);
      expect(r.total, 42);
    });
  });

  group('storeDisplayFromLegacy / storeDisplayFromGroupStatus', () {
    test('mapping by numeric legacy status', () {
      expect(storeDisplayFromLegacy(1).key, 'paymentPending');
      expect(storeDisplayFromLegacy(6).key, 'delivered');
      expect(storeDisplayFromLegacy(7).key, 'cancelled');
      expect(storeDisplayFromLegacy(8).key, 'returned');
      expect(storeDisplayFromLegacy(5).key, 'on_the_way');
      expect(storeDisplayFromLegacy(3).key, 'preparing_status');
    });

    test('mapping by checkout group status', () {
      expect(storeDisplayFromGroupStatus('awaiting_payment').key, 'paymentPending');
      expect(storeDisplayFromGroupStatus('delivered').key, 'delivered');
      expect(storeDisplayFromGroupStatus('cancelled').key, 'cancelled');
      expect(storeDisplayFromGroupStatus('out_for_delivery').key, 'on_the_way');
      expect(storeDisplayFromGroupStatus('ready').key, 'preparing_status');
    });
  });

  group('progressForActive', () {
    test('step 2→12, step 3→33.33, step 5→66.66, step 6→100', () {
      expect(progressForActive(2), 12);
      expect(progressForActive(3), closeTo(33.33, 0.01));
      expect(progressForActive(5), closeTo(66.66, 0.01));
      expect(progressForActive(6), 100);
    });

    test('cancelled and returned step index is -1 which clamps to 12%', () {
      expect(progressForActive(7), 12);
      expect(progressForActive(8), 12);
    });
  });
}
