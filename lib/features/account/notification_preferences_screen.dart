import 'package:flutter/material.dart';

import '../../core/app_controller.dart';

/// Customer-controlled push notification preferences (marketing vs order
/// updates) — wired to the backend (`/customer/notification_preferences`).
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _pushMarketing = true;
  bool _pushTransactional = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await appController.api.getNotificationPreferences();
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _pushMarketing = _flag(result.dataMap['push_marketing']);
        _pushTransactional = _flag(result.dataMap['push_transactional']);
      }
      _loading = false;
    });
  }

  bool _flag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = '$value'.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  Future<void> _toggleMarketing(bool value) async => _save(marketing: value);
  Future<void> _toggleTransactional(bool value) async =>
      _save(transactional: value);

  Future<void> _save({bool? marketing, bool? transactional}) async {
    final previousMarketing = _pushMarketing;
    final previousTransactional = _pushTransactional;
    setState(() {
      _saving = true;
      if (marketing != null) _pushMarketing = marketing;
      if (transactional != null) _pushTransactional = transactional;
    });
    final result = await appController.api.saveNotificationPreferences(
      pushMarketing: marketing,
      pushTransactional: transactional,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!result.ok) {
        _pushMarketing = previousMarketing;
        _pushTransactional = previousTransactional;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? appController.t('notif_preferences_saved')
              : result.message.isNotEmpty
                  ? result.message
                  : appController.t('something_went_wrong'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('notif_preferences_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text(app.t('notif_push_marketing')),
                        subtitle: Text(app.t('notif_push_marketing_subtitle')),
                        value: _pushMarketing,
                        onChanged: _saving ? null : _toggleMarketing,
                        secondary: const Icon(Icons.campaign_outlined),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: Text(app.t('notif_push_transactional')),
                        subtitle: Text(app.t('notif_push_transactional_subtitle')),
                        value: _pushTransactional,
                        onChanged: _saving ? null : _toggleTransactional,
                        secondary: const Icon(Icons.local_shipping_outlined),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
