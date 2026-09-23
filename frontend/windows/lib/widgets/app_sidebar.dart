import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

enum NmeSection { library, playlists, sync }

class AppSidebar extends StatelessWidget {
  final NmeSection selected;
  final ValueChanged<NmeSection> onSelect;

  const AppSidebar({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 212,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Glass(
          borderRadius: BorderRadius.circular(20),
          blur: 30,
          tintOpacity: 0.05,
          child: Column(
            children: [
              const SizedBox(height: 18),
              _Brand(),
              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.white.withOpacity(0.08)),
              const SizedBox(height: 10),
              _NavItem(
                label: 'Library',
                icon: Icons.menu,
                active: selected == NmeSection.library,
                onTap: () => onSelect(NmeSection.library),
              ),
              _NavItem(
                label: 'Playlists',
                icon: Icons.play_arrow,
                active: selected == NmeSection.playlists,
                onTap: () => onSelect(NmeSection.playlists),
              ),
              _NavItem(
                label: 'Sync & Settings',
                icon: Icons.sync,
                active: selected == NmeSection.sync,
                onTap: () => onSelect(NmeSection.sync),
              ),
              const Spacer(),
              const _StorageFooter(),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentDim],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Text('N', style: AppText.mono(size: 12, color: const Color(0xFF1A1208), weight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Text('NME', style: AppText.ui(size: 15, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? Colors.white.withOpacity(0.14)
        : hovering
            ? Colors.white.withOpacity(0.07)
            : Colors.transparent;
    final fg = widget.active || hovering ? AppColors.textPrimary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.active ? Colors.white.withOpacity(0.18) : Colors.transparent),
            ),
            child: Row(
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: AppText.ui(size: 13.5, color: fg),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 15, color: fg),
                      const SizedBox(width: 10),
                      Text(widget.label),
                    ],
                  ),
                ),
                const Spacer(),
                AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  scale: widget.active ? 1 : 0,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageFooter extends StatelessWidget {
  const _StorageFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: Color(0x1FFFFFFF)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Offline storage', style: AppText.mono(size: 10.5, color: AppColors.textTertiary)),
              Text('4.1 / 10 GB', style: AppText.mono(size: 10.5, color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 0.41),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
