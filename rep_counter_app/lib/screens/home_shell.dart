import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'exercises/catalog_tab.dart';
import 'history/history_tab.dart';
import 'routines/routines_tab.dart';
import 'settings_screen.dart';

/// Rutinas · Ejercicios · Historial.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});

  final int initialTab;

  /// Lets a tab send the user to another one ("Entrenamiento libre" opens
  /// Ejercicios).
  static void selectTab(BuildContext context, int index) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(index);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialTab;

  void _select(int index) => setState(() => _index = index);

  static const _labels = ['Rutinas', 'Ejercicios', 'Historial'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: const [RoutinesTab(), CatalogTab(), HistoryTab()],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == _index,
                    child: Pressable(
                      onTap: () => _select(i),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: i == _index ? c.mark : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          _labels[i],
                          style: AppText.text(
                            16,
                            weight: i == _index
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: i == _index ? c.ink : c.ink2,
                          ),
                        ),
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

/// Header of the three tabs: title on the left, sensor and settings on the
/// right.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.only(left: kGutter, right: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppText.text(28, weight: FontWeight.w500, color: c.ink),
              ),
            ),
            const SensorBadge(),
            IconTapTarget(
              icon: AppIconKind.settings,
              label: 'Ajustes',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
