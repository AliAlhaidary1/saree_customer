import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/json_util.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'complaint';
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _subject;
  late final TextEditingController _message;
  late final TextEditingController _orderId;
  bool _sending = false;

  List<Map<String, dynamic>> _mine = [];
  bool _loadingMine = false;

  @override
  void initState() {
    super.initState();
    final user = appController.user;
    _name = TextEditingController(text: J.str(user?['name']));
    _phone = TextEditingController(text: J.str(user?['mobile']));
    _email = TextEditingController(text: J.str(user?['email']));
    _subject = TextEditingController();
    _message = TextEditingController();
    _orderId = TextEditingController();
    if (appController.isLoggedIn) _loadMine();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    _orderId.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    setState(() => _loadingMine = true);
    try {
      final res = await appController.api.myComplaints();
      if (!mounted) return;
      var items = res.dataMaps;
      if (items.isEmpty) {
        final paged = J.maps(res.dataMap['data']);
        if (paged.isNotEmpty) items = paged;
      }
      setState(() => _mine = items);
    } catch (_) {
      // keep list empty on failure
    } finally {
      if (mounted) setState(() => _loadingMine = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _sending = true);
    try {
      final res = await appController.api.submitComplaint(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        type: _type,
        subject: _subject.text.trim(),
        message: _message.text.trim(),
        orderId: _orderId.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.ok
              ? res.message.isNotEmpty
                  ? res.message
                  : appController.t('complaint_sent_success')
              : (res.message.isNotEmpty
                  ? res.message
                  : appController.t('something_went_wrong'))),
        ),
      );
      if (res.ok) {
        _subject.clear();
        _message.clear();
        _orderId.clear();
        if (appController.isLoggedIn) _loadMine();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appController.t('something_went_wrong'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return appController.t('complaint_status_in_progress');
      case 'resolved':
        return appController.t('complaint_status_resolved');
      case 'rejected':
        return appController.t('complaint_status_rejected');
      default:
        return appController.t('complaint_status_new');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('complaints_suggestions'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(app.t('complaints_hero_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'complaint',
                    label: Text(app.t('complaint')),
                    icon: const Icon(Icons.report_problem_outlined)),
                ButtonSegment(
                    value: 'suggestion',
                    label: Text(app.t('suggestion')),
                    icon: const Icon(Icons.lightbulb_outline)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(labelText: app.t('Name')),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? app.t('field_required') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: app.t('mobile_number')),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? app.t('field_required') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: app.t('email')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _subject,
                    decoration: InputDecoration(
                        labelText:
                            '${app.t('complaint_subject')} (${app.t('optional')})'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _orderId,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: app.t('order_number_optional')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _message,
                    maxLines: 5,
                    decoration: InputDecoration(
                        labelText: app.t('complaint_message_hint')),
                    validator: (v) =>
                        (v == null || v.trim().length < 5) ? app.t('field_required') : null,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: Text(app.t('send')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(app.t('my_submissions'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!app.isLoggedIn)
              Text(app.t('complaint_login_hint'),
                  style: Theme.of(context).textTheme.bodySmall)
            else if (_loadingMine)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator()))
            else if (_mine.isEmpty)
              Text(app.t('no_submissions_yet'),
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ..._mine.map((item) {
                final status = J.str(item['status'], 'new');
                final type = J.str(item['type'], 'complaint');
                final reply = J.str(item['admin_reply']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Chip(
                              label: Text(type == 'suggestion'
                                  ? app.t('suggestion')
                                  : app.t('complaint')),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Spacer(),
                            Text(_statusLabel(status),
                                style: TextStyle(
                                    color: _statusColor(status),
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (J.str(item['subject']).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(J.str(item['subject']),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        const SizedBox(height: 4),
                        Text(J.str(item['message'])),
                        if (reply.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.verified_outlined,
                                    size: 16, color: Colors.green),
                                const SizedBox(width: 6),
                                Expanded(child: Text(reply)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
