import SwiftUI

struct SettingsScreen: View {
    @Environment(GymRepository.self) private var repo
    @Environment(AuthController.self) private var auth
    @Environment(SettingsController.self) private var settings
    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c

    /// Tries to upload pending changes first; if some cannot go up, asks
    /// before deleting them along with this phone's copy of the account.
    private func signOut() async {
        if repo.pendingChanges > 0 { await repo.sync() }
        let pending = repo.pendingChanges
        if pending > 0 {
            let ok = await confirm(
                title: "¿Cerrar sesión sin subir todo?",
                message: "Hay \(pending) \(plural(pending, "cambio", "cambios")) que todavía no llegó al "
                    + "servidor, probablemente por falta de internet. Si cierras sesión ahora, se pierden.",
                confirmLabel: "Cerrar sesión"
            )
            if !ok { return }
        }
        sensor.cancel()
        repo.discardUserData()
        // The app returns to the login screen on its own when the session ends.
        await auth.signOut()
    }

    private func accountRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Text(label).font(.text(16)).foregroundStyle(c.ink2)
            Text(value)
                .font(.text(17, .medium))
                .foregroundStyle(c.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 64)
        .bottomRule(c.line)
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 8)
                    Text("Ajustes")
                        .font(.text(36, .medium))
                        .foregroundStyle(c.ink)
                    Spacer().frame(height: 32)
                    AppLabel("Apariencia")
                    Spacer().frame(height: 4)
                    HStack {
                        Text("Modo oscuro")
                            .font(.text(19, .medium))
                            .foregroundStyle(c.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AppSwitch(value: settings.darkMode, label: "Modo oscuro") { settings.setDarkMode($0) }
                    }
                    .frame(height: 84)
                    .bottomRule(c.line)
                    Spacer().frame(height: 32)
                    AppLabel("Cuenta")
                    Spacer().frame(height: 4)
                    accountRow("Nombre", auth.user?.name ?? "—")
                    accountRow("Correo", auth.user?.email ?? "—")
                    Spacer().frame(height: 32)
                    AppLabel("Sincronización")
                    Spacer().frame(height: 4)
                    SyncStatusRow()
                }
                .padding(.horizontal, kGutter)
            }
            SecondaryButton("Cerrar sesión") { Task { await signOut() } }
                .padding(EdgeInsets(top: 16, leading: kGutter, bottom: 32, trailing: kGutter))
        }
    }
}

private struct SyncStatusRow: View {
    @Environment(GymRepository.self) private var repo
    @Environment(\.colors) private var c

    private var status: String {
        let pending = repo.pendingChanges
        switch repo.syncStatus {
        case .syncing: return "Sincronizando…"
        case .offline: return "Sin conexión. Se reintenta solo."
        case .error: return "El servidor no respondió bien. Se reintenta solo."
        case .idle where pending > 0:
            return "\(pending) \(plural(pending, "cambio pendiente", "cambios pendientes"))"
        case .idle:
            guard let last = repo.lastSyncedAt else { return "Todavía no se sincroniza." }
            let parts = Calendar.current.dateComponents([.hour, .minute], from: last)
            return "Al día · \(formatDay(last)), \(parts.hour ?? 0):\(String(format: "%02d", parts.minute ?? 0))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status)
                    .font(.text(17, .medium))
                    .foregroundStyle(c.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextAction(label: "Sincronizar", colorKey: \.ink, weight: .semibold,
                           action: repo.syncStatus == .syncing ? nil : { Task { await repo.sync() } })
            }
            if let issue = repo.syncIssue {
                Text(issue).font(.text(14)).foregroundStyle(c.ink2)
            }
        }
        .padding(.vertical, 14)
        .bottomRule(c.line)
    }
}
