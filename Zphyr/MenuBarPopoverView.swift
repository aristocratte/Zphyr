//
//  MenuBarPopoverView.swift
//  Zphyr
//

import SwiftUI
import Combine

@MainActor
final class MenuBarPopoverStore: ObservableObject {
    @Published var snapshot = MenuBarUsageSnapshot()
    @Published var modelStatus: ModelStatus = .notDownloaded
    @Published var isMainWindowVisible = false
}

struct MenuBarUsageSnapshot {
    var primaryModelDiskBytes: Int64 = 0
    var formatterModelDiskBytes: Int64 = 0
    var processRAMBytes: Int64 = 0
    var totalRAMBytes: Int64 = 0
    var processCPUPercent: Double = 0
    var maxCPUPercent: Double = 100
    var primaryModelInstalled = false
    var primaryModelFolderAvailable = false
    var formatterModelInstalled = false

    var totalModelDiskBytes: Int64 {
        max(0, primaryModelDiskBytes) + max(0, formatterModelDiskBytes)
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var store: MenuBarPopoverStore

    let onToggleMainWindow: () -> Void
    let onLoadPrimaryModel: () -> Void
    let onOpenPrimaryModelFolder: () -> Void
    let onQuit: () -> Void

    private var loadButtonTitle: String {
        switch store.modelStatus {
        case .ready:
            return t("Modèle prêt", "Model ready", "Modelo listo", "模型就绪", "モデル準備完了", "Модель готова")
        case .downloading, .loading:
            return t("Chargement…", "Loading…", "Cargando…", "加载中…", "読み込み中…", "Загрузка…")
        case .failed:
            return t("Réessayer", "Retry", "Reintentar", "重试", "再試行", "Повторить")
        case .notDownloaded:
            return t("Télécharger modèle", "Download model", "Descargar modelo", "下载模型", "モデルをダウンロード", "Скачать модель")
        }
    }

    private var loadButtonEnabled: Bool {
        switch store.modelStatus {
        case .ready, .downloading, .loading:
            return false
        case .failed, .notDownloaded:
            return true
        }
    }

    private var ramRatio: Double {
        guard store.snapshot.totalRAMBytes > 0 else { return 0 }
        return clamp(Double(store.snapshot.processRAMBytes) / Double(store.snapshot.totalRAMBytes))
    }

    private var cpuRatio: Double {
        guard store.snapshot.maxCPUPercent > 0 else { return 0 }
        return clamp(store.snapshot.processCPUPercent / store.snapshot.maxCPUPercent)
    }

    private var donutSlices: [DonutSlice] {
        let values: [(label: String, value: Int64, color: Color)] = [
            ("Whisper", max(0, store.snapshot.primaryModelDiskBytes), Color(hex: "#0A84FF")),
            ("Qwen formatage", max(0, store.snapshot.formatterModelDiskBytes), Color(hex: "#22D3B8"))
        ]
        let total = Double(values.reduce(0) { $0 + $1.value })
        guard total > 0 else { return [] }

        var running = 0.0
        return values.compactMap { item in
            guard item.value > 0 else { return nil }
            let fraction = Double(item.value) / total
            defer { running += fraction }
            return DonutSlice(
                label: item.label,
                value: item.value,
                start: running,
                end: running + fraction,
                color: item.color
            )
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            modelUsageCard
            runtimeCard
            actionsGrid
        }
        .padding(12)
        .frame(width: 352)
        .background(
            LinearGradient(
                colors: [Color(hex: "#FCFCFD"), Color(hex: "#F3F5F8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#0A84FF"), Color(hex: "#22D3B8")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Zphyr")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#141416"))
                Text(t("Moniteur local des modèles", "Local model monitor", "Monitor local de modelos", "本地模型监控", "ローカルモデルモニター", "Локальный монитор моделей"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#74777D"))
                    .lineLimit(1)
            }

            Spacer()

            statusPill
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let (text, tint): (String, Color) = {
            switch store.modelStatus {
            case .ready:
                return (t("Prêt", "Ready", "Listo", "就绪", "準備完了", "Готово"), Color(hex: "#34C759"))
            case .downloading, .loading:
                return (t("Actif", "Active", "Activo", "活动", "動作中", "Активно"), Color(hex: "#0A84FF"))
            case .failed:
                return (t("Erreur", "Error", "Error", "错误", "エラー", "Ошибка"), Color(hex: "#FF3B30"))
            case .notDownloaded:
                return (t("Hors-ligne", "Offline", "Sin conexión", "离线", "オフライン", "Офлайн"), Color(hex: "#8E8E93"))
            }
        }()

        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }

    private var modelUsageCard: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "#E6E9EE"), lineWidth: 16)
                        .frame(width: 132, height: 132)

                    ForEach(donutSlices) { slice in
                        DonutArcShape(start: slice.start, end: slice.end)
                            .stroke(
                                slice.color,
                                style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 132, height: 132)
                    }

                    VStack(spacing: 2) {
                        Text(t("Modèles", "Models", "Modelos", "模型", "モデル", "Модели"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "#80848D"))
                        Text(formatBytes(store.snapshot.totalModelDiskBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#141416"))
                    }
                }
                .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 10) {
                    legendRow(
                        color: Color(hex: "#0A84FF"),
                        title: "Whisper v3 Turbo",
                        value: formatInstalledSize(
                            bytes: store.snapshot.primaryModelDiskBytes,
                            installed: store.snapshot.primaryModelInstalled
                        )
                    )
                    legendRow(
                        color: Color(hex: "#22D3B8"),
                        title: t("Qwen formatage", "Qwen formatting", "Qwen de formateo", "Qwen 格式化", "Qwen フォーマット", "Qwen форматирования"),
                        value: formatInstalledSize(
                            bytes: store.snapshot.formatterModelDiskBytes,
                            installed: store.snapshot.formatterModelInstalled
                        )
                    )
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private var runtimeCard: some View {
        HStack(spacing: 10) {
            MetricRingCard(
                title: "RAM",
                value: formatBytes(store.snapshot.processRAMBytes),
                subtitle: "\(t("sur", "of", "de", "占", "中", "из")) \(formatBytes(store.snapshot.totalRAMBytes))",
                progress: ramRatio,
                color: Color(hex: "#30D158")
            )

            MetricRingCard(
                title: "CPU",
                value: String(format: "%.1f%%", store.snapshot.processCPUPercent),
                subtitle: "\(t("sur", "of", "de", "占", "中", "из")) \(Int(store.snapshot.maxCPUPercent))%",
                progress: cpuRatio,
                color: Color(hex: "#FF9F0A")
            )
        }
    }

    private var actionsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            Button(
                store.isMainWindowVisible
                    ? t("Masquer app", "Hide app", "Ocultar app", "隐藏应用", "アプリを隠す", "Скрыть app")
                    : t("Ouvrir app", "Open app", "Abrir app", "打开应用", "アプリを開く", "Открыть app")
            ) {
                onToggleMainWindow()
            }
            .buttonStyle(PopoverActionButtonStyle(icon: "macwindow"))

            Button(loadButtonTitle) {
                onLoadPrimaryModel()
            }
            .buttonStyle(PopoverActionButtonStyle(icon: "arrow.down.circle"))
            .disabled(!loadButtonEnabled)

            Button(t("Ouvrir dossier", "Open folder", "Abrir carpeta", "打开文件夹", "フォルダを開く", "Открыть папку")) {
                onOpenPrimaryModelFolder()
            }
            .buttonStyle(PopoverActionButtonStyle(icon: "folder"))
            .disabled(!store.snapshot.primaryModelFolderAvailable)

            Button(t("Quitter", "Quit", "Salir", "退出", "終了", "Выйти")) {
                onQuit()
            }
            .buttonStyle(PopoverActionButtonStyle(icon: "power"))
        }
    }

    private func legendRow(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#1B1D21"))
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#7E838B"))
                    .lineLimit(1)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: "#E8EBF0"), lineWidth: 1)
            )
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func formatInstalledSize(bytes: Int64, installed: Bool) -> String {
        guard installed else {
            return t("Non installé", "Not installed", "No instalado", "未安装", "未インストール", "Не установлен")
        }
        guard bytes > 0 else {
            return t("Installé (taille inconnue)", "Installed (size unknown)", "Instalado (tamaño desconocido)", "已安装（大小未知）", "インストール済み（サイズ不明）", "Установлен (размер неизвестен)")
        }
        return formatBytes(bytes)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

private struct DonutSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Int64
    let start: Double
    let end: Double
    let color: Color
}

private struct DonutArcShape: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5
        let startAngle = Angle(degrees: -90 + 360 * start)
        let endAngle = Angle(degrees: -90 + 360 * end)
        p.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return p
    }
}

private struct MetricRingCard: View {
    let title: String
    let value: String
    let subtitle: String
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color(hex: "#E8EBF0"), lineWidth: 6)
                    .frame(width: 42, height: 42)
                DonutArcShape(start: 0, end: min(1, max(0, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(0.3))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#737780"))
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#141416"))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(hex: "#8D9198"))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color(hex: "#E8EBF0"), lineWidth: 1)
                )
        )
    }
}

private struct PopoverActionButtonStyle: ButtonStyle {
    let icon: String

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(Color(hex: "#1C1D20"))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(configuration.isPressed ? Color(hex: "#E7ECF3") : Color(hex: "#EEF2F8"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: "#DCE2EA"), lineWidth: 1)
        )
    }
}
