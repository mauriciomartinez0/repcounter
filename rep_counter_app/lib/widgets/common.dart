// Building blocks shared by the screens. Sizes come from the style guide:
// 24 side margin, 72 primary button, 56 text field, radius 6, 1 px lines.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../screens/connection_screen.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';

/// Uppercase 12 px label ("PESO USADO").
class AppLabel extends StatelessWidget {
  const AppLabel(this.text, {super.key, this.color, this.textAlign});

  final String text;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        textAlign: textAlign,
        style: AppText.label(color ?? context.colors.ink3),
      );
}

/// Tap target without ripple. The design has no shadows or ink effects; a
/// slight opacity change acknowledges the press.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 80),
          opacity: _down ? 0.6 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 72,
    this.fontSize = 22,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !busy;
    return Pressable(
      onTap: enabled ? onPressed : null,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.btnBg,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: busy
              ? SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.btnInk,
                  ),
                )
              : Text(
                  label,
                  style: AppText.text(fontSize,
                      weight: FontWeight.w600, color: c.btnInk),
                ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 64,
    this.fontSize = 18,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;
  final AppIconKind? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: c.control),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, color: c.ink),
              const SizedBox(width: 12),
            ],
            Text(
              label,
              style: AppText.text(fontSize, weight: FontWeight.w600, color: c.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48 px outlined button for secondary actions in a row ("Editar").
class SmallButton extends StatelessWidget {
  const SmallButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: c.control),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Text(label,
            style: AppText.text(16, weight: FontWeight.w600, color: c.ink)),
      ),
    );
  }
}

/// A plain text action ("¿La olvidaste?", "Cancelar").
class TextAction extends StatelessWidget {
  const TextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.weight = FontWeight.w400,
    this.size = 16,
    this.underline = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final FontWeight weight;
  final double size;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.colors.ink2;
    return Pressable(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            style: AppText.text(size, weight: weight, color: color).copyWith(
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.trailing,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadius),
      borderSide: BorderSide(color: c.control),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: AppLabel(label)),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 56,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            onSubmitted: onSubmitted,
            style: AppText.text(17, color: c.ink),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.text(17, color: c.ink2),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: c.ink, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Search field with the surface fill used in the catalog.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hint = 'Buscar ejercicio',
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadius),
      borderSide: BorderSide(color: c.control),
    );
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AppText.text(17, color: c.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.text(17, color: c.ink2),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: c.ink, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Dot plus "SENSOR". Filled when connected, hollow when not. Tapping it
/// while disconnected opens the connection screen.
class SensorBadge extends StatelessWidget {
  const SensorBadge({super.key, this.interactive = true});

  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final sensor = context.app.sensor;
    return ListenableBuilder(
      listenable: sensor,
      builder: (context, _) {
        final c = context.colors;
        final connected = sensor.connected;
        final badge = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? c.dot : Colors.transparent,
                border: Border.all(
                  color: connected
                      ? (c.dotRing.a == 0 ? c.dot : c.dotRing)
                      : c.ink2,
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('SENSOR', style: AppText.label(c.ink2)),
          ],
        );
        return Semantics(
          label: connected ? 'Sensor conectado' : 'Sensor sin conectar',
          child: interactive && !connected
              ? Pressable(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConnectionScreen(popOnConnect: true),
                    ),
                  ),
                  child: SizedBox(height: 44, child: badge),
                )
              : ExcludeSemantics(child: badge),
        );
      },
    );
  }
}

class IconTapTarget extends StatelessWidget {
  const IconTapTarget({
    super.key,
    required this.icon,
    required this.onTap,
    required this.label,
    this.color,
  });

  final AppIconKind icon;
  final VoidCallback? onTap;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: AppIcon(icon, color: color ?? context.colors.ink),
          ),
        ),
      );
}

/// Back chevron on the left, sensor badge (and optional extras) on the right.
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, this.onBack, this.actions = const []});

  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: kGutter),
          child: Row(
            children: [
              IconTapTarget(
                icon: AppIconKind.back,
                label: 'Volver',
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              ...actions,
              const SensorBadge(),
            ],
          ),
        ),
      );
}

/// "Cancelar · Título · Guardar".
class ModalHeader extends StatelessWidget {
  const ModalHeader({
    super.key,
    required this.title,
    this.onCancel,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final VoidCallback? onCancel;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Row(
          children: [
            TextAction(
              label: 'Cancelar',
              onPressed: onCancel ?? () => Navigator.of(context).maybePop(),
            ),
            // Without an action the title sits after "Cancelar"; with one
            // it is centered between both.
            if (actionLabel == null) const SizedBox(width: 56),
            Expanded(
              child: Text(
                title,
                textAlign:
                    actionLabel == null ? TextAlign.start : TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.text(17, weight: FontWeight.w600, color: c.ink),
              ),
            ),
            if (actionLabel != null)
              TextAction(
                label: actionLabel!,
                onPressed: onAction,
                color: onAction == null ? c.ink3 : c.mark,
                weight: FontWeight.w600,
              ),
          ],
        ),
      ),
    );
  }
}

/// Outlined chip with an icon ("Press de banca" in Recientes).
class OutlineChip extends StatelessWidget {
  const OutlineChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final AppIconKind? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: c.control),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: 22, color: c.ink),
              const SizedBox(width: 8),
            ],
            Text(label, style: AppText.text(15, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

/// Filled chip used for filters and segment choices. Selected chips invert.
class FillChip extends StatelessWidget {
  const FillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.fontSize = 15,
  });

  final String label;
  final bool selected;
  final AppIconKind? icon;
  final VoidCallback? onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.bg : c.ink;
    return Pressable(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? c.ink : c.surface,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                AppIcon(icon!, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Text(label, style: AppText.text(fontSize, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of chips that scrolls past the right edge, as in the
/// designs, while starting aligned with the side margin.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, this.spacing = 8});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              children[i],
            ],
          ],
        ),
      );
}

class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: checked ? c.btnBg : Colors.transparent,
        border: Border.all(color: checked ? c.btnBg : c.control, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: checked
          ? Center(
              child: AppIcon(AppIconKind.check,
                  size: 20, color: c.btnInk, strokeWidth: 2),
            )
          : null,
    );
  }
}

/// Theme switch as drawn in Ajustes: 68 × 40 track, 28 px knob.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: value,
      label: label,
      child: Pressable(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 68,
          height: 40,
          decoration: BoxDecoration(
            color: value ? c.btnBg : c.surface,
            border: Border.all(color: value ? c.btnBg : c.control, width: 1.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(4.5),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? c.btnInk : c.control,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Big number with a small unit next to it ("60 kg").
class NumberWithUnit extends StatelessWidget {
  const NumberWithUnit({
    super.key,
    required this.value,
    this.unit,
    this.size = 40,
    this.unitSize = 15,
    this.color,
  });

  final String value;
  final String? unit;
  final double size;
  final double unitSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: value,
          style: AppText.number(size, color: color ?? c.ink),
        ),
        if (unit != null)
          TextSpan(
            text: ' $unit',
            style: AppText.text(unitSize, color: c.ink2),
          ),
      ]),
      maxLines: 1,
    );
  }
}

/// − value + control for weights.
class WeightStepper extends StatelessWidget {
  const WeightStepper({
    super.key,
    required this.valueKg,
    required this.onChanged,
    this.large = true,
    this.step = 2.5,
  });

  /// Null means body weight; the buttons then add load.
  final double? valueKg;
  final ValueChanged<double?> onChanged;
  final bool large;
  final double step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final box = large ? 72.0 : 56.0;
    final value = valueKg;

    Widget button(AppIconKind icon, String label, VoidCallback? onTap) =>
        Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Container(
              width: box,
              height: box,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Center(
                child: AppIcon(icon, size: large ? 28 : 24, color: c.ink),
              ),
            ),
          ),
        );

    return Row(
      mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment:
          large ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
      children: [
        button(
          AppIconKind.minus,
          'Bajar peso',
          value == null
              ? null
              : () => onChanged(value - step <= 0 ? null : value - step),
        ),
        SizedBox(
          width: large ? null : 108,
          child: Center(
            child: value == null
                ? Text('Corporal',
                    style: AppText.number(large ? 48 : 30, color: c.ink))
                : NumberWithUnit(
                    value: formatKg(value),
                    unit: 'kg',
                    size: large ? 80 : 40,
                    unitSize: large ? 20 : 15,
                  ),
          ),
        ),
        button(
          AppIconKind.plus,
          'Subir peso',
          () => onChanged((value ?? 0) + step),
        ),
      ],
    );
  }

}

/// − value + for whole numbers, such as correcting the reps of a set.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.label = 'repeticiones',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  /// For screen readers: "Quitar una repetición".
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget button(AppIconKind icon, String semantic, VoidCallback? onTap) =>
        Pressable(
          onTap: onTap,
          semanticLabel: semantic,
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Center(child: AppIcon(icon, color: c.ink)),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(AppIconKind.minus, 'Quitar una de $label',
            value > min ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 72,
          child: Center(
            child: Text('$value', style: AppText.number(40, color: c.ink)),
          ),
        ),
        button(AppIconKind.plus, 'Sumar una de $label',
            value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

/// A labelled stat used in the rest screen, summary and progress.
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.footnote,
    this.footnoteColor,
    this.valueSize = 40,
    this.valueColor,
  });

  final String label;
  final Widget? value;
  final String? unit;
  final String? footnote;
  final Color? footnoteColor;
  final double valueSize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLabel(label),
        const SizedBox(height: 6),
        ?value,
        if (footnote != null) ...[
          const SizedBox(height: 6),
          Text(footnote!,
              style: AppText.text(14,
                  weight: footnoteColor != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: footnoteColor ?? c.ink3)),
        ],
      ],
    );
  }
}

/// Two stats side by side with a vertical rule between, framed by lines.
class StatPair extends StatelessWidget {
  const StatPair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: c.line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 16, 20),
                child: left,
              ),
            ),
            Container(width: 1, color: c.line),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 0, 20),
                child: right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin progress track (calibration, rest timer).
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({
    super.key,
    required this.value,
    this.height = 4,
    this.fill,
  });

  final double value;
  final double height;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: c.track),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: fill ?? c.ink),
          ),
        ],
      ),
    );
  }
}

/// Asks before leaving a screen with unsaved or in-progress work.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title,
          style: AppText.text(22, weight: FontWeight.w600, color: c.ink)),
      content: Text(message, style: AppText.text(16, color: c.ink2)),
      actions: [
        TextAction(
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 8),
        TextAction(
          label: confirmLabel,
          color: c.ink,
          weight: FontWeight.w600,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Light haptic tick, used when a rep lands or a timer ends.
void tick() => HapticFeedback.lightImpact();
