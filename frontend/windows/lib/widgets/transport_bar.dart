import 'package:flutter/material.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

class TransportBar extends StatelessWidget {
  final Track? nowPlaying;
  final bool isPlaying;
  final VoidCallback onPlayPause;

  const TransportBar({
    super.key,
    required this.nowPlaying,
    required this.isPlaying,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Glass(
        borderRadius: BorderRadius.circular(20),
        blur: 30,
        tintOpacity: 0.06,
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(width: 230, child: _NowPlaying(track: nowPlaying)),
              Expanded(child: _Controls(isPlaying: isPlaying, onPlayPause: onPlayPause)),
              SizedBox(
                width: 230,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.circle, size: 6, color: AppColors.vu),
                    const SizedBox(width: 6),
                    Text('synced', style: AppText.mono(size: 10.5, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  final Track? track;
  const _NowPlaying({required this.track});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
            gradient: const LinearGradient(
              colors: [Color(0xFF3A352C), Color(0xFF201D18)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track?.title ?? 'Nothing playing',
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(size: 13),
              ),
              const SizedBox(height: 2),
              Text(
                track?.artist ?? 'Select a track from your library',
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(size: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  const _Controls({required this.isPlaying, required this.onPlayPause});

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _TransportIconButton(icon: Icons.skip_previous),
            const SizedBox(width: 6),
            GestureDetector(
              onTapDown: (_) => setState(() => pressed = true),
              onTapUp: (_) => setState(() => pressed = false),
              onTapCancel: () => setState(() => pressed = false),
              onTap: widget.onPlayPause,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedScale(
                  scale: pressed ? 0.9 : 1,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        widget.isPlaying ? Icons.pause : Icons.play_arrow,
                        key: ValueKey(widget.isPlaying),
                        size: 16,
                        color: const Color(0xFF181008),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const _TransportIconButton(icon: Icons.skip_next),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 480,
          child: Row(
            children: [
              Text('0:00', style: AppText.mono(size: 10.5, color: AppColors.textTertiary)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 0.34),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation(
                          widget.isPlaying ? AppColors.accent : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('3:12', style: AppText.mono(size: 10.5, color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransportIconButton extends StatefulWidget {
  final IconData icon;
  const _TransportIconButton({required this.icon});

  @override
  State<_TransportIconButton> createState() => _TransportIconButtonState();
}

class _TransportIconButtonState extends State<_TransportIconButton> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      cursor: SystemMouseCursors.click,
      child: IconButton(
        icon: AnimatedScale(
          scale: hovering ? 1.12 : 1,
          duration: const Duration(milliseconds: 130),
          child: Icon(
            widget.icon,
            size: 18,
            color: hovering ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        onPressed: () {},
      ),
    );
  }
}
