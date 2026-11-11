import 'package:flutter/material.dart';

import '../core/app_controller.dart';

/// A tiny Wi‑Fi status badge — the only connectivity signal shown to the
/// user, deliberately rendered WITHOUT any text (no "online"/"offline",
/// no "أنت دون اتصال", no banner). The icon alone communicates state:
///
///   green Wifi        – the device reaches the internet (fresh data will
///                       paint; the catalog refresh runs normally),
///   orange WifiOff    – the device appears to have no internet access; the
///                       screens fall back to the last saved rows without
///                       ever telling the user their connection is "off" or
///                       that content is "stale"/"offline".
///
/// Lives next to the platform-hours line on the home card. Listens to the
/// [ConnectivityService] instance directly so it flips the moment
/// connectivity_plus reports an interface change + the probe confirms.
class ConnectivityBadge extends StatelessWidget {
  const ConnectivityBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appController.connectivity,
      builder: (_, _) {
        final online = appController.isOnline;
        final color = online ? Colors.green.shade700 : Colors.orange.shade800;
        final bg = online ? Colors.green.shade50 : Colors.orange.shade50;
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            border: Border.all(color: color, width: 1.4),
          ),
          child: Icon(
            online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 15,
            color: color,
          ),
        );
      },
    );
  }
}
