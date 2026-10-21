import SwiftUI

/// Screen that fills the viewport but scrolls when the keyboard needs room,
/// keeping its last child pinned to the bottom.
struct FullHeightScroll<Content: View>: View {
    var padding = EdgeInsets(top: 0, leading: kGutter, bottom: 32, trailing: kGutter)
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(padding)
                    .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

struct OrDivider: View {
    @Environment(\.colors) private var c

    var body: some View {
        HStack(spacing: 16) {
            Rectangle().fill(c.line).frame(height: 1)
            Text("o").font(.text(14)).foregroundStyle(c.ink3)
            Rectangle().fill(c.line).frame(height: 1)
        }
        .padding(.vertical, 20)
    }
}

/// "¿No tienes cuenta? Crear cuenta".
struct AuthSwitchLine: View {
    let question: String
    let action: String
    let onTap: () -> Void
    @Environment(\.colors) private var c

    var body: some View {
        HStack(spacing: 0) {
            Text("\(question) ").font(.text(16)).foregroundStyle(c.ink2)
            TextAction(label: action, colorKey: \.ink, weight: .semibold, underline: true, action: onTap)
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
func goToConnectionAfterAuth() {
    Router.shared.reset(to: .connection)
}

struct LoginScreen: View {
    @Environment(AuthController.self) private var auth
    @Environment(\.colors) private var c
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await action()
                goToConnectionAfterAuth()
            } catch let error as AuthError {
                showMessage(error.message)
            } catch {}
        }
    }

    private func signIn() {
        run { try await auth.signIn(email, password) }
    }

    var body: some View {
        FullHeightScroll {
            Spacer().frame(height: 72)
            Text("Inicia sesión")
                .font(.text(40, .medium))
                .foregroundStyle(c.ink)
            Spacer().frame(height: 8)
            Text("Tus rutinas y tu historial se guardan en tu cuenta.")
                .font(.text(17))
                .foregroundStyle(c.ink2)
            Spacer().frame(height: 40)
            AppTextField(label: "Correo", hint: "nombre@correo.com", text: $email, focus: $emailFocused,
                         keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never,
                         submitLabel: .next, onSubmit: { passwordFocused = true })
            Spacer().frame(height: 20)
            AppTextField(label: "Contraseña", hint: "Tu contraseña", text: $password, focus: $passwordFocused,
                         secure: true, contentType: .password, capitalization: .never,
                         submitLabel: .done, onSubmit: signIn) {
                TextAction(label: "¿La olvidaste?", size: 14, underline: true) {
                    showMessage("Recuperar la contraseña todavía no está disponible: "
                        + "falta configurar el envío de correos.")
                }
                .frame(height: 16)
            }
            Spacer().frame(height: 24)
            PrimaryButton("Entrar", busy: busy, action: signIn)
            OrDivider()
            SecondaryButton("Continuar con Google", action: busy ? nil : {
                run { try await auth.signInWithGoogle() }
            })
            Spacer(minLength: 24)
            AuthSwitchLine(question: "¿No tienes cuenta?", action: "Crear cuenta") {
                Router.shared.push(.register)
            }
        }
        .onAppear {
            if auth.sessionExpired {
                showMessage("Tu sesión terminó. Vuelve a iniciar sesión.")
            }
        }
    }
}

struct RegisterScreen: View {
    @Environment(AuthController.self) private var auth
    @Environment(\.colors) private var c
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @FocusState private var nameFocused: Bool
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await action()
                goToConnectionAfterAuth()
            } catch let error as AuthError {
                showMessage(error.message)
            } catch {}
        }
    }

    private func submit() {
        run { try await auth.signUp(name, email, password) }
    }

    var body: some View {
        FullHeightScroll {
            IconTapTarget(icon: .back, label: "Volver a iniciar sesión") { Router.shared.pop() }
                .offset(x: -12)
                .frame(height: 56)
            Spacer().frame(height: 16)
            Text("Crea tu cuenta")
                .font(.text(40, .medium))
                .foregroundStyle(c.ink)
            Spacer().frame(height: 32)
            AppTextField(label: "Nombre", hint: "Cómo te llamas", text: $name, focus: $nameFocused,
                         contentType: .name, capitalization: .words, submitLabel: .next,
                         onSubmit: { emailFocused = true })
            Spacer().frame(height: 20)
            AppTextField(label: "Correo", hint: "nombre@correo.com", text: $email, focus: $emailFocused,
                         keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never,
                         submitLabel: .next, onSubmit: { passwordFocused = true })
            Spacer().frame(height: 20)
            AppTextField(label: "Contraseña", hint: "Mínimo 8 caracteres", text: $password,
                         focus: $passwordFocused, secure: true, contentType: .newPassword,
                         capitalization: .never, submitLabel: .done, onSubmit: submit)
            Spacer().frame(height: 24)
            PrimaryButton("Crear cuenta", busy: busy, action: submit)
            OrDivider()
            SecondaryButton("Continuar con Google", action: busy ? nil : {
                run { try await auth.signInWithGoogle() }
            })
            Spacer(minLength: 24)
            AuthSwitchLine(question: "¿Ya tienes cuenta?", action: "Inicia sesión") {
                Router.shared.pop()
            }
        }
    }
}
