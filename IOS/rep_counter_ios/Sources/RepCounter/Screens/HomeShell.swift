import SwiftUI

/// Rutinas · Ejercicios · Historial.
struct HomeShell: View {
    @Bindable private var router = Router.shared
    @Environment(\.colors) private var c

    private static let labels = ["Rutinas", "Ejercicios", "Historial"]

    var body: some View {
        VStack(spacing: 0) {
            // All three stay alive, like an IndexedStack, so each keeps its
            // scroll position and filters.
            ZStack {
                RoutinesTab().opacity(router.homeTab == 0 ? 1 : 0).allowsHitTesting(router.homeTab == 0)
                CatalogTab().opacity(router.homeTab == 1 ? 1 : 0).allowsHitTesting(router.homeTab == 1)
                HistoryTab().opacity(router.homeTab == 2 ? 1 : 0).allowsHitTesting(router.homeTab == 2)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 0) {
                ForEach(0..<Self.labels.count, id: \.self) { i in
                    let selected = i == router.homeTab
                    Pressable(action: { router.homeTab = i }) {
                        Text(Self.labels[i])
                            .font(.text(16, selected ? .semibold : .medium))
                            .foregroundStyle(selected ? c.ink : c.ink2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .top) {
                                Rectangle().fill(selected ? c.mark : .clear).frame(height: 2)
                            }
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(height: 72)
            .topRule(c.line)
        }
    }
}

/// Header of the three tabs: title on the left, sensor and settings on the
/// right.
struct TabHeader: View {
    let title: String
    @Environment(\.colors) private var c

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.text(28, .medium))
                .foregroundStyle(c.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            SensorBadge()
            IconTapTarget(icon: .settings, label: "Ajustes") { Router.shared.push(.settings) }
        }
        .padding(.leading, kGutter)
        .padding(.trailing, 12)
        .frame(height: 72)
    }
}
