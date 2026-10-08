import 'app_controller.dart';

/// Shared Akhdimni order-status labels (Arabic / English).
/// Parity with saree_front `src/components/akhdimni/orderStatus.js`.
const Map<String, String> akhdimniStatusLabelsAr = {
  'draft': 'مسودة',
  'pending': 'يتم التجهيز',
  'pending_review': 'يتم التجهيز',
  'priced': 'تم التسعير',
  'awaiting_customer_approval': 'بانتظار موافقتك',
  'approved': 'يتم التجهيز',
  'assigned': 'يتم التجهيز',
  'picked_up': 'في الطريق',
  'out_for_delivery': 'في الطريق',
  'in_progress': 'في الطريق',
  'delivered': 'تم التسليم',
  'completed': 'تم التسليم',
  'cancelled': 'ملغي',
  'rejected': 'مرفوض',
  'failed': 'فشل',
};

const Map<String, String> akhdimniStatusLabelsEn = {
  'draft': 'Draft',
  'pending': 'Being prepared',
  'pending_review': 'Being prepared',
  'priced': 'Priced',
  'awaiting_customer_approval': 'Awaiting your approval',
  'approved': 'Being prepared',
  'assigned': 'Being prepared',
  'picked_up': 'On the way',
  'out_for_delivery': 'On the way',
  'in_progress': 'On the way',
  'delivered': 'Delivered',
  'completed': 'Delivered',
  'cancelled': 'Cancelled',
  'rejected': 'Rejected',
  'failed': 'Failed',
};

String akhdimniStatusLabel(String? status) {
  final s = '$status';
  final map = appController.i18n.code == 'ar'
      ? akhdimniStatusLabelsAr
      : akhdimniStatusLabelsEn;
  return map[s] ?? s;
}

bool akhdimniIsTerminalFail(String? status) =>
    status == 'cancelled' || status == 'rejected' || status == 'failed';

/// Timeline step index: 0 preparing, 1 on the way, 2 delivered.
int akhdimniStepIndex(String? status) {
  if (status == 'completed' || status == 'delivered') return 2;
  if (status == 'in_progress' ||
      status == 'picked_up' ||
      status == 'out_for_delivery') {
    return 1;
  }
  return 0;
}

/// Backend AkhdimniApiController::cancel يقبل pending/assigned فقط.
const List<String> akhdimniCancellableStatuses = [
  'pending',
  'assigned',
];
