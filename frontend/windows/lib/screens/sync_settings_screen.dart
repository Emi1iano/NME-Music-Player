import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  bool wifiOnly = true;
  bool autoDownload = false;
  bool backgroundSync = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sync & Settings', style: AppText.ui(size: 20, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Last synced 2 minutes ago', style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
                ],
              ),
              _SyncNowButton(),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _DevicesPanel()),
                  const SizedBox(width: 16),
                  Expanded(child: _SessionStatsPanel()),
                ],
              ),
              const SizedBox(height: 16),
              _Panel(
                title: 'Sync preferences',
                child: Column(
                  children: [
                    _ToggleRow(
                      label: 'Sync on Wi-Fi only',
                      desc: 'Pause background sync on cellular',
                      value: wifiOnly,
                      onChanged: (v) => setState(() => wifiOnly = v),
                    ),
                    _ToggleRow(
                      label: 'Auto-download new tracks',
                      desc: 'Cache new library additions for offline playback',
                      value: autoDownload,
                      onChanged: (v) => setState(() => autoDownload = v),
                    ),
                    _ToggleRow(
                      label: 'Background sync',
                      desc: 'Keep syncing while NME is minimized',
                      value: backgroundSync,
                      onChanged: (v) => setState(() => backgroundSync = v),
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncNowButton extends StatefulWidget {
  @override
  State<_SyncNowButton> createState() => _SyncNowButtonState();
}

class _SyncNowButtonState extends State<_SyncNowButton> {
  bool hovering = false;
  bool spinning = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // TODO: trigger a real sync cycle against the Zig server here.
          setState(() => spinning = true);
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted) setState(() => spinning = false);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: hovering ? AppColors.accentDim : Colors.white.withOpacity(0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedRotation(
                turns: spinning ? 1 : 0,
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOut,
                child: Icon(Icons.sync, size: 14, color: hovering ? AppColors.accent : AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              Text('Sync now', style: AppText.ui(size: 12.5, color: hovering ? AppColors.accent : AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Panel({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.ui(size: 13, weight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppText.ui(size: 11.5, color: AppColors.textTertiary)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DevicesPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Devices',
      subtitle: 'Music and playtime stats sync across these',
      child: Column(
        children: const [
          _DeviceRow(name: 'This PC — Windows', status: 'Synced just now', icon: Icons.laptop_windows, stale: false),
          _DeviceRow(name: "Nedved's Phone", status: 'Synced 2 min ago', icon: Icons.phone_iphone, stale: false),
          _DeviceRow(name: "Mariano's Laptop", status: 'Offline · queued', icon: Icons.laptop_mac, stale: true, isLast: true),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final String name;
  final String status;
  final IconData icon;
  final bool stale;
  final bool isLast;

  const _DeviceRow({
    required this.name,
    required this.status,
    required this.icon,
    required this.stale,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(icon, size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: AppText.ui(size: 13)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: stale ? AppColors.textTertiary : AppColors.vu),
                    const SizedBox(width: 6),
                    Text(status, style: AppText.ui(size: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionStatsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'This session',
      subtitle: 'Transfer since last connection',
      child: Column(
        children: const [
          _StatRow(label: 'Tracks pulled', value: '3'),
          _StatRow(label: 'Playtime stats merged', value: '17 events'),
          _StatRow(label: 'Data transferred', value: '6.2 MB'),
          _StatRow(label: 'Conflicts resolved', value: '0'),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.ui(size: 12.5, color: AppColors.textTertiary)),
          Text(value, style: AppText.mono(size: 11.5)),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const _ToggleRow({
    required this.label,
    required this.desc,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppText.ui(size: 13)),
                const SizedBox(height: 2),
                Text(desc, style: AppText.ui(size: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
            activeTrackColor: AppColors.accentDim.withOpacity(0.4),
            inactiveThumbColor: AppColors.textSecondary,
            inactiveTrackColor: Colors.white.withOpacity(0.10),
          ),
        ],
      ),
    );
  }
}
