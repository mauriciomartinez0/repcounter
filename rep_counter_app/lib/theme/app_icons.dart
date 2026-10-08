// Icons from the style guide: 24 box, 1.75 stroke, round ends, no fill.
// The lime dot (the sensor) only appears in the three placement icons.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';

enum AppIconKind {
  back('<path d="M15 5l-7 7 7 7"/>'),
  forward('<path d="M9 5l7 7-7 7"/>'),
  plus('<path d="M12 5v14M5 12h14"/>'),
  minus('<path d="M5 12h14"/>'),
  settings(
    '<path d="M4 8h10M18 8h2M4 16h2M10 16h10"/>'
    '<circle cx="16" cy="8" r="2"/><circle cx="8" cy="16" r="2"/>',
  ),
  dragHandle('<path d="M5 9h14M5 15h14"/>'),
  check('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  play('<path d="M9 6.5v11l9-5.5z" fill="currentColor"/>'),
  pause('<path d="M9 6v12M15 6v12"/>'),
  star(
    '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9'
    '-4.3-4.1 5.9-.8z" fill="currentColor"/>',
  ),
  starOutline(
    '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9'
    '-4.3-4.1 5.9-.8z"/>',
  ),
  arrowUp('<path d="M12 19V5M6 11l6-6 6 6"/>'),
  arrowDown('<path d="M12 5v14M6 13l6 6 6-6"/>'),

  // Equipment type.
  barbell('<path d="M2 12h20M4.5 7v10M7.5 9v6M19.5 7v10M16.5 9v6"/>'),
  dumbbell(
    '<path d="M9 12h6"/><rect x="4.5" y="7.5" width="4.5" height="9" rx="1.25"/>'
    '<rect x="15" y="7.5" width="4.5" height="9" rx="1.25"/>',
  ),
  machine(
    '<rect x="7" y="7" width="10" height="13" rx="1.25"/>'
    '<path d="M7 11.5h10M7 16h10M12 7V3M9 3h6"/>',
  ),
  bodyweight(
    '<circle cx="12" cy="4.5" r="2"/>'
    '<path d="M12 7.5V15M6.5 10h11M12 15l-3.5 6M12 15l3.5 6"/>',
  ),
  cable(
    '<circle cx="12" cy="6.5" r="3.5"/>'
    '<path d="M8.5 6.5V18M6 18h5M15.5 6.5V13"/>',
  ),

  // Sensor placement. {DOT} is replaced with the sensor dot.
  placementArm(
    '<path d="M5 3v8a3 3 0 0 0 3 3h10"/><circle cx="20" cy="14" r="2"/>'
    '<circle cx="13" cy="14" r="3" {DOT}/>',
  ),
  placementBody(
    '<circle cx="12" cy="5" r="2.5"/>'
    '<path d="M6.5 21v-6.5a5.5 5.5 0 0 1 11 0V21"/>'
    '<circle cx="12" cy="17.5" r="3" {DOT}/>',
  ),
  placementEquipment(
    '<path d="M2 12h20M4.5 7v10M7.5 9v6M19.5 7v10M16.5 9v6"/>'
    '<circle cx="12" cy="12" r="3" {DOT}/>',
  );

  const AppIconKind(this.body);
  final String body;
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.kind, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 1.75,
  });

  final AppIconKind kind;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = color ?? DefaultTextStyle.of(context).style.color ?? c.ink;
    final ring = c.dotRing.a == 0 ? 'none' : _hex(c.dotRing);
    final body = kind.body.replaceAll(
      '{DOT}',
      'fill="${_hex(c.dot)}" stroke="$ring" stroke-width="1.25"',
    );
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="$strokeWidth" '
        'stroke-linecap="round" stroke-linejoin="round">$body</svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: ink),
    );
  }
}
