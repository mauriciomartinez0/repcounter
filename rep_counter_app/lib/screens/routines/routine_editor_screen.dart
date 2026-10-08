import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../exercises/exercise_picker_screen.dart';

/// Create or edit a routine. Drag to reorder, swipe left to remove, tap a
/// value to change it.
class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, this.routine});

  /// Null creates a new routine.
  final Routine? routine;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _Entry {
  _Entry(this.key, this.item);
  final int key;
  RoutineItem item;
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.routine?.name ?? '');
  late final List<_Entry> _entries = [
    for (final (i, item) in (widget.routine?.items ?? const []).indexed)
      _Entry(i, item),
  ];
  late int _nextKey = _entries.length;
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _changed(VoidCallback change) => setState(() {
        change();
        _dirty = true;
      });

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Ponle un nombre a la rutina.');
      return;
    }
    setState(() => _saving = true);
    await context.app.repository.saveRoutine(Routine(
      id: widget.routine?.id ?? '',
      name: name,
      items: [for (final e in _entries) e.item],
    ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _leave() async {
    if (!_dirty ||
        await confirm(
          context,
          title: '¿Descartar cambios?',
          message: 'Lo que cambiaste en esta rutina no se guardará.',
          confirmLabel: 'Descartar',
          cancelLabel: 'Seguir editando',
        )) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final routine = widget.routine;
    if (routine == null) return;
    final ok = await confirm(
      context,
      title: '¿Eliminar "${routine.name}"?',
      message: 'El historial de sesiones con esta rutina se conserva.',
      confirmLabel: 'Eliminar',
    );
    if (!ok || !mounted) return;
    await context.app.repository.deleteRoutine(routine.id);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _addExercises() async {
    final repo = context.app.repository;
    final name = _name.text.trim();
    final picked = await Navigator.of(context).push<List<Exercise>>(
      MaterialPageRoute(
        builder: (_) => ExercisePickerScreen(
          title: name.isEmpty ? 'Agregar ejercicios' : 'Agregar a $name',
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    _changed(() {
      for (final exercise in picked) {
        _entries.add(_Entry(
          _nextKey++,
          RoutineItem(
            exerciseId: exercise.id,
            weightKg: exercise.equipment == Equipment.bodyweight
                ? null
                : repo.lastWeight(exercise.id) ?? 20,
          ),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repo = context.app.repository;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ModalHeader(
                title: widget.routine == null ? 'Nueva rutina' : 'Editar rutina',
                onCancel: _leave,
                actionLabel: 'Guardar',
                onAction: _saving ? null : _save,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppLabel('Nombre'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _name,
                      onChanged: (_) => _dirty = true,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppText.text(26,
                          weight: FontWeight.w500, color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'Nombre de la rutina',
                        hintStyle: AppText.text(26,
                            weight: FontWeight.w500, color: c.ink3),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: c.control),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: c.ink, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: c.line),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _entries.length,
                  onReorder: (from, to) => _changed(() {
                    if (to > from) to--;
                    _entries.insert(to, _entries.removeAt(from));
                  }),
                  proxyDecorator: (child, _, _) => Material(
                    color: c.surface,
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final exercise = repo.exercise(entry.item.exerciseId);
                    return _EditorRow(
                      key: ValueKey(entry.key),
                      index: index,
                      name: exercise?.name ?? entry.item.exerciseId,
                      item: entry.item,
                      onChanged: (item) => _changed(() => entry.item = item),
                      onRemove: () => _changed(() => _entries.remove(entry)),
                    );
                  },
                  footer: Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SecondaryButton(
                          label: 'Agregar ejercicio',
                          icon: AppIconKind.plus,
                          onPressed: _addExercises,
                        ),
                        if (widget.routine != null) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: TextAction(
                              label: 'Eliminar rutina',
                              onPressed: _delete,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorRow extends StatelessWidget {
  const _EditorRow({
    super.key,
    required this.index,
    required this.name,
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final String name;
  final RoutineItem item;
  final ValueChanged<RoutineItem> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dismissible(
      key: ValueKey('dismiss-$key'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        color: c.btnBg,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        child: Text('Eliminar',
            style: AppText.text(16, weight: FontWeight.w600, color: c.btnInk)),
      ),
      child: Container(
        height: 116,
        padding: const EdgeInsets.only(left: 12, right: kGutter),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Arrastrar para reordenar: $name',
                child: SizedBox(
                  width: 44,
                  height: 64,
                  child: Center(
                    child: AppIcon(AppIconKind.dragHandle, color: c.ink2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.text(17,
                          weight: FontWeight.w500, color: c.ink)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _Cell(
                        label: 'Series',
                        value: '${item.sets}',
                        onTap: () async {
                          final v = await _askInt(context, 'Series', item.sets,
                              min: 1, max: 20);
                          if (v != null) onChanged(item.copyWith(sets: v));
                        },
                      ),
                      const SizedBox(width: 8),
                      _Cell(
                        label: 'Reps',
                        value: '${item.reps}',
                        onTap: () async {
                          final v = await _askInt(context, 'Repeticiones',
                              item.reps,
                              min: 1, max: 100);
                          if (v != null) onChanged(item.copyWith(reps: v));
                        },
                      ),
                      const SizedBox(width: 8),
                      _Cell(
                        label: 'Peso',
                        value: item.weightKg == null
                            ? 'Corp.'
                            : '${formatKg(item.weightKg!)} kg',
                        onTap: () async {
                          final result = await _askWeight(context, item.weightKg);
                          if (result != null) {
                            onChanged(item.copyWith(weightKg: () => result.$1));
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      _Cell(
                        label: 'Descanso',
                        value: formatClock(item.restSeconds),
                        onTap: () async {
                          final v = await _askRest(context, item.restSeconds);
                          if (v != null) {
                            onChanged(item.copyWith(restSeconds: v));
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        semanticLabel: '$label: $value. Cambiar',
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  maxLines: 1,
                  style: AppText.label(c.ink2, size: 10)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: AppText.number(21, color: c.ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small dialog with one text field. Returns the parsed value, or null if
/// cancelled.
Future<T?> _askValue<T>(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  required TextInputType keyboard,
  required T? Function(String text) parse,
  required String error,
  String? footnote,
}) {
  final controller = TextEditingController(text: initial);
  String? message;
  return showDialog<T>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.colors;
        void submit() {
          final value = parse(controller.text.trim());
          if (value == null) {
            setState(() => message = error);
          } else {
            Navigator.of(context).pop(value);
          }
        }

        return AlertDialog(
          title: Text(title,
              style: AppText.text(22, weight: FontWeight.w600, color: c.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: keyboard,
                onSubmitted: (_) => submit(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,:]')),
                ],
                style: AppText.number(40, color: c.ink),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: AppText.number(40, color: c.ink3),
                  errorText: message,
                ),
              ),
              if (footnote != null) ...[
                const SizedBox(height: 8),
                Text(footnote, style: AppText.text(14, color: c.ink2)),
              ],
            ],
          ),
          actions: [
            TextAction(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            TextAction(
              label: 'Listo',
              color: c.ink,
              weight: FontWeight.w600,
              onPressed: submit,
            ),
          ],
        );
      },
    ),
  ).whenComplete(controller.dispose);
}

Future<int?> _askInt(BuildContext context, String title, int initial,
        {required int min, required int max}) =>
    _askValue<int>(
      context,
      title: title,
      initial: '$initial',
      hint: '$initial',
      keyboard: TextInputType.number,
      error: 'Entre $min y $max.',
      parse: (text) {
        final v = int.tryParse(text);
        return v == null || v < min || v > max ? null : v;
      },
    );

/// Returns a record so "body weight" (null) can be told apart from cancel.
Future<(double?,)?> _askWeight(BuildContext context, double? initial) =>
    _askValue<(double?,)>(
      context,
      title: 'Peso (kg)',
      initial: initial == null ? '' : formatKg(initial),
      hint: '0',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
      error: 'Escribe un peso entre 0 y 500.',
      footnote: 'Déjalo vacío o en 0 para peso corporal.',
      parse: (text) {
        if (text.isEmpty) return (null,);
        final v = double.tryParse(text.replaceAll(',', '.'));
        if (v == null || v < 0 || v > 500) return null;
        return (v == 0 ? null : v,);
      },
    );

Future<int?> _askRest(BuildContext context, int initial) => _askValue<int>(
      context,
      title: 'Descanso',
      initial: formatClock(initial),
      hint: '1:30',
      keyboard: TextInputType.datetime,
      error: 'Usa minutos:segundos, por ejemplo 1:30.',
      footnote: 'Minutos y segundos, por ejemplo 1:30.',
      parse: (text) {
        final parts = text.split(':');
        int? seconds;
        if (parts.length == 1) {
          seconds = int.tryParse(parts[0]);
        } else if (parts.length == 2) {
          final m = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
          final s = int.tryParse(parts[1]);
          if (m != null && s != null && s < 60) seconds = m * 60 + s;
        }
        return seconds == null || seconds < 0 || seconds > 900
            ? null
            : seconds;
      },
    );
