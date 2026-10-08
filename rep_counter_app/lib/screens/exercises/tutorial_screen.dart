import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

/// Tutorial: video plus key points.
///
/// There are no videos yet; the player shows the layout and runs its clock
/// so the screen can be reviewed. Once the backend serves
/// [Exercise.videoUrl], swap the placeholder for the video_player package.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  Timer? _timer;
  int _position = 0;

  int get _length => widget.exercise.tutorialSeconds;
  bool get _playing => _timer != null;

  void _toggle() {
    setState(() {
      if (_playing) {
        _timer!.cancel();
        _timer = null;
        return;
      }
      if (_position >= _length) _position = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _position++;
          if (_position >= _length) {
            _timer?.cancel();
            _timer = null;
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = widget.exercise.tutorialSteps;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 32),
                children: [
                  Text(widget.exercise.name,
                      style: AppText.text(36,
                          weight: FontWeight.w500, height: 1.1, color: c.ink)),
                  const SizedBox(height: 6),
                  Text('Tutorial', style: AppText.text(16, color: c.ink2)),
                  const SizedBox(height: 24),
                  if (_length > 0)
                    Container(
                      height: 204,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.control),
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppLabel('Video del tutorial', color: c.ink2),
                          Expanded(
                            child: Center(
                              child: Pressable(
                                onTap: _toggle,
                                semanticLabel:
                                    _playing ? 'Pausar video' : 'Reproducir video',
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _playing ? null : c.btnBg,
                                    border: _playing
                                        ? Border.all(color: c.ink, width: 1.5)
                                        : null,
                                  ),
                                  child: Center(
                                    child: AppIcon(
                                      _playing
                                          ? AppIconKind.pause
                                          : AppIconKind.play,
                                      color: _playing ? c.ink : c.btnInk,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          DefaultTextStyle(
                            style: AppText.text(13, color: c.ink2),
                            child: Row(
                              children: [
                                Text(formatClock(_position)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ProgressTrack(
                                    value: _position / _length,
                                    height: 3,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(formatClock(_length)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (steps.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    const AppLabel('Puntos clave'),
                    const SizedBox(height: 8),
                    for (final (i, step) in steps.indexed)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          border: i == steps.length - 1
                              ? null
                              : Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text('${i + 1}',
                                  style: AppText.number(26, color: c.ink3)),
                            ),
                            Expanded(
                              child: Text(step,
                                  style: AppText.text(17, color: c.ink)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
