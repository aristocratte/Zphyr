//
//  AccountView.swift
//  Zphyr
//
//  Dev-mode login: credentials stored in UserDefaults (no real backend).
//  Toggle DEV_MODE to swap in a real auth layer later.
//

import SwiftUI

// MARK: - Auth state

@Observable
@MainActor
final class AuthState {
    static let shared = AuthState()
    private init() { load() }

    var isLoggedIn: Bool = false
    var email: String = ""
    var displayName: String = ""
    var plan: String = "Beta"
    var avatarInitials: String {
        let parts = displayName.split(separator: " ")
        return parts.compactMap { $0.first.map(String.init) }.prefix(2).joined().uppercased()
    }

    // Dev-mode credentials (accepted as valid)
    private let devEmail    = "dev@zphyr.app"
    private let devPassword = "zphyr2026"

    func login(email: String, password: String) -> Bool {
        let ok = (email.lowercased() == devEmail && password == devPassword)
            || (!email.isEmpty && password.count >= 4)   // any creds work in dev
        if ok {
            self.email = email
            self.displayName = email.components(separatedBy: "@").first?
                .replacingOccurrences(of: ".", with: " ")
                .capitalized ?? email
            self.plan = email == devEmail ? "Dev" : "Beta"
            self.isLoggedIn = true
            save()
        }
        return ok
    }

    func logout() {
        isLoggedIn = false
        email = ""
        displayName = ""
        UserDefaults.standard.removeObject(forKey: "zphyr.auth.email")
        UserDefaults.standard.removeObject(forKey: "zphyr.auth.name")
        UserDefaults.standard.removeObject(forKey: "zphyr.auth.plan")
    }

    private func save() {
        UserDefaults.standard.set(email, forKey: "zphyr.auth.email")
        UserDefaults.standard.set(displayName, forKey: "zphyr.auth.name")
        UserDefaults.standard.set(plan, forKey: "zphyr.auth.plan")
    }

    private func load() {
        if let e = UserDefaults.standard.string(forKey: "zphyr.auth.email"), !e.isEmpty {
            email = e
            displayName = UserDefaults.standard.string(forKey: "zphyr.auth.name") ?? e
            plan = UserDefaults.standard.string(forKey: "zphyr.auth.plan") ?? "Beta"
            isLoggedIn = true
        }
    }
}

// MARK: - AccountView

struct AccountView: View {
    @Bindable private var appState = AppState.shared
    private var auth: AuthState { AuthState.shared }

    var body: some View {
        let _ = appState.selectedLanguage.id
        if auth.isLoggedIn {
            ProfileView()
        } else {
            LoginView()
        }
    }
}

// MARK: - Login

private struct LoginView: View {
    private var auth: AuthState { AuthState.shared }

    @State private var email = ""
    @State private var password = ""
    @State private var error = ""
    @State private var isLoading = false
    @FocusState private var focused: LoginField?

    enum LoginField { case email, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Logo
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#2C2C2C"), Color(hex: "#1A1A1A")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(spacing: 4) {
                        Text(t("Connexion à Zphyr", "Sign in to Zphyr", "Iniciar sesión en Zphyr", "登录 Zphyr", "Zphyr にサインイン", "Вход в Zphyr"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text(t("Mode développeur actif", "Developer mode enabled", "Modo desarrollador activo", "开发者模式已启用", "開発者モード有効", "Режим разработчика включен"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#888880"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#FF9500").opacity(0.12))
                            .foregroundColor(Color(hex: "#FF9500"))
                            .cornerRadius(6)
                    }
                }

                // Form
                VStack(spacing: 12) {
                    // Email
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Adresse email", "Email address", "Correo electrónico", "邮箱地址", "メールアドレス", "Адрес email"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#888880"))
                        HStack(spacing: 8) {
                            Image(systemName: "envelope")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "#AAAAAA"))
                            TextField("dev@zphyr.app", text: $email)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .focused($focused, equals: .email)
                                .onSubmit { focused = .password }
                                .textContentType(.emailAddress)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focused == .email ? Color(hex: "#1A1A1A").opacity(0.3) : Color.clear, lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
                    }

                    // Password
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Mot de passe", "Password", "Contraseña", "密码", "パスワード", "Пароль"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#888880"))
                        HStack(spacing: 8) {
                            Image(systemName: "lock")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "#AAAAAA"))
                            SecureField("••••••••", text: $password)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .focused($focused, equals: .password)
                                .onSubmit { tryLogin() }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focused == .password ? Color(hex: "#1A1A1A").opacity(0.3) : Color.clear, lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
                    }

                    // Error
                    if !error.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(Color(hex: "#FF3B30"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#FF3B30").opacity(0.08))
                        .cornerRadius(8)
                    }

                    // Submit
                    Button {
                        tryLogin()
                    } label: {
                        HStack(spacing: 6) {
                            if isLoading {
                                ProgressView().scaleEffect(0.75).tint(.white)
                            }
                            Text(isLoading
                                 ? t("Connexion…", "Signing in…", "Iniciando sesión…", "登录中…", "サインイン中…", "Вход…")
                                 : t("Se connecter", "Sign in", "Iniciar sesión", "登录", "サインイン", "Войти"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(email.isEmpty || password.isEmpty ? Color(hex: "#BBBBBB") : Color(hex: "#1A1A1A"))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                }

                // Dev hint
                VStack(spacing: 4) {
                    Text(t("Identifiants dev disponibles", "Available dev credentials", "Credenciales dev disponibles", "可用开发者凭据", "開発用認証情報", "Доступные dev-учетные данные"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#AAAAAA"))
                    Text("dev@zphyr.app · zphyr2026")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "#BBBBBB"))
                    Text(t("(ou n'importe quel email + mot de passe ≥ 4 caractères)",
                           "(or any email + password with at least 4 characters)",
                           "(o cualquier email + contraseña de al menos 4 caracteres)",
                           "（或任意邮箱 + 至少 4 位密码）",
                           "（または任意のメール + 4文字以上のパスワード）",
                           "(или любой email + пароль от 4 символов)"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .background(Color(hex: "#FF9500").opacity(0.06))
                .cornerRadius(10)
            }
            .padding(32)
            .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#F7F7F5"))
        .onAppear { focused = .email }
    }

    private func tryLogin() {
        error = ""
        isLoading = true
        // Simulate async (would be real network call)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            let ok = AuthState.shared.login(email: email, password: password)
            if !ok {
                error = t("Identifiants incorrects.", "Invalid credentials.", "Credenciales incorrectas.", "凭据无效。", "認証情報が正しくありません。", "Неверные учетные данные.")
            }
            isLoading = false
        }
    }
}

// MARK: - Profile

private struct ProfileView: View {
    private var auth: AuthState { AuthState.shared }
    private var store: TranscriptionStore { TranscriptionStore.shared }
    @State private var showLogoutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {

                // Avatar + name
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#1A1A1A"))
                            .frame(width: 72, height: 72)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        Text(auth.avatarInitials.isEmpty ? "?" : auth.avatarInitials)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(spacing: 4) {
                        Text(auth.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text(auth.email)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#888880"))
                        Text(auth.plan)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(auth.plan == "Dev" ? Color(hex: "#FF9500") : Color(hex: "#007AFF"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                (auth.plan == "Dev" ? Color(hex: "#FF9500") : Color(hex: "#007AFF")).opacity(0.1)
                            )
                            .cornerRadius(20)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Usage stats
                HStack(spacing: 12) {
                    MiniStat(value: "\(store.totalTranscriptions)", label: t("Dictées", "Dictations", "Dictados", "听写次数", "音声入力回数", "Диктовки"))
                    MiniStat(value: "\(store.totalWords)", label: t("Mots", "Words", "Palabras", "词数", "単語数", "Слова"))
                    MiniStat(value: store.minutesSaved < 1 ? "0m" : "\(Int(store.minutesSaved))m", label: t("Temps gagné", "Time saved", "Tiempo ahorrado", "节省时间", "節約時間", "Сэкономлено времени"))
                }

                // Info cards
                VStack(spacing: 10) {
                    InfoRow(icon: "cpu", label: t("Modèle", "Model", "Modelo", "模型", "モデル", "Модель"), value: "Whisper large-v3-turbo")
                    InfoRow(icon: "lock.shield", label: t("Stockage", "Storage", "Almacenamiento", "存储", "ストレージ", "Хранилище"), value: t("100% local", "100% local", "100% local", "100% 本地", "100% ローカル", "100% локально"))
                    InfoRow(icon: "tag", label: t("Version", "Version", "Versión", "版本", "バージョン", "Версия"), value: "0.1 Beta")
                    InfoRow(icon: "person.fill", label: t("Mode", "Mode", "Modo", "模式", "モード", "Режим"), value: t("Développeur", "Developer", "Desarrollador", "开发者", "開発者", "Разработчик"))
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)

                // Logout
                Button {
                    showLogoutConfirm = true
                } label: {
                    Label(t("Se déconnecter", "Sign out", "Cerrar sesión", "退出登录", "サインアウト", "Выйти"), systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF3B30"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#FF3B30").opacity(0.08))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .confirmationDialog(t("Se déconnecter ?", "Sign out?", "¿Cerrar sesión?", "退出登录？", "サインアウトしますか？", "Выйти?"), isPresented: $showLogoutConfirm) {
                    Button(t("Se déconnecter", "Sign out", "Cerrar sesión", "退出登录", "サインアウト", "Выйти"), role: .destructive) { AuthState.shared.logout() }
                    Button(t("Annuler", "Cancel", "Cancelar", "取消", "キャンセル", "Отмена"), role: .cancel) {}
                }
            }
            .padding(28)
        }
        .background(Color(hex: "#F7F7F5"))
    }
}

// MARK: - Small helpers

private struct MiniStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundColor(Color(hex: "#1A1A1A"))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#AAAAAA"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#AAAAAA"))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#888880"))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1A1A"))
        }
    }
}

#Preview {
    AccountView()
        .frame(width: 640, height: 560)
}
