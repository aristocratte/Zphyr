//
//  L10n.swift
//  Zphyr
//

import Foundation

/// Languages with full UI copy support in this app.
enum SupportedUILanguage: String {
    case fr
    case en
    case es
    case zh
    case ja
    case ru

    static func fromWhisperCode(_ code: String) -> SupportedUILanguage {
        let normalized = code.lowercased()
        if normalized.hasPrefix("fr") { return .fr }
        if normalized.hasPrefix("en") { return .en }
        if normalized.hasPrefix("es") { return .es }
        if normalized.hasPrefix("zh") { return .zh }
        if normalized.hasPrefix("ja") { return .ja }
        if normalized.hasPrefix("ru") { return .ru }

        // Fallback policy requested by product: keep EN/FR when a feature is not localized.
        return .en
    }

    var localeIdentifier: String {
        switch self {
        case .fr: return "fr_FR"
        case .en: return "en_US"
        case .es: return "es_ES"
        case .zh: return "zh_Hans"
        case .ja: return "ja_JP"
        case .ru: return "ru_RU"
        }
    }
}

enum SnippetTriggerKind: Hashable {
    case linkedIn
    case social
    case gmail
}

enum L10n {
    private static let snippetTriggerTable: [SupportedUILanguage: [SnippetTriggerKind: String]] = [
        .fr: [
            .linkedIn: """
ajoute-nous sur linkedin
suivez-nous sur linkedin
retrouve-nous sur linkedin
""",
            .social: """
ajoute-nous sur notre réseau social
ajoute-nous sur nos réseaux sociaux
suis-nous sur notre réseau social
""",
            .gmail: """
contacte-nous sur notre gmail
écris-nous sur notre gmail
envoie-nous un mail sur notre gmail
"""
        ],
        .en: [
            .linkedIn: """
add us on linkedin
follow us on linkedin
find us on linkedin
""",
            .social: """
add us on social media
follow us on social media
find us on social media
""",
            .gmail: """
contact us on gmail
email us on gmail
send us an email on gmail
"""
        ],
        .es: [
            .linkedIn: """
añádenos en linkedin
síguenos en linkedin
encuéntranos en linkedin
""",
            .social: """
añádenos en redes sociales
síguenos en redes sociales
encuéntranos en redes sociales
""",
            .gmail: """
contáctanos por gmail
escríbenos por gmail
envíanos un correo por gmail
"""
        ],
        .zh: [
            .linkedIn: """
在领英上关注我们
在linkedin上关注我们
通过领英联系我们
""",
            .social: """
在社交媒体上关注我们
关注我们的社交账号
在我们的社交网络找到我们
""",
            .gmail: """
通过gmail联系我们
给我们的gmail发邮件
通过gmail给我们写信
"""
        ],
        .ja: [
            .linkedIn: """
linkedinで私たちをフォローしてください
linkedinでつながってください
linkedinで私たちを見つけてください
""",
            .social: """
SNSで私たちをフォローしてください
私たちのSNSをチェックしてください
SNSで私たちを見つけてください
""",
            .gmail: """
gmailでご連絡ください
gmailでメールしてください
gmailでお問い合わせください
"""
        ],
        .ru: [
            .linkedIn: """
добавьте нас в linkedin
подпишитесь на нас в linkedin
найдите нас в linkedin
""",
            .social: """
добавьте нас в соцсети
подпишитесь на нас в соцсетях
найдите нас в наших соцсетях
""",
            .gmail: """
свяжитесь с нами через gmail
напишите нам на gmail
отправьте нам письмо на gmail
"""
        ]
    ]

    @MainActor
    static var uiLanguage: SupportedUILanguage {
        AppState.shared.uiDisplayLanguage
    }

    @MainActor
    static var uiLocale: Locale {
        Locale(identifier: uiLanguage.localeIdentifier)
    }

    @MainActor
    static func ui(
        _ fr: String,
        _ en: String,
        _ es: String,
        _ zh: String,
        _ ja: String,
        _ ru: String
    ) -> String {
        ui(
            for: AppState.shared.uiDisplayLanguage.rawValue,
            fr: fr,
            en: en,
            es: es,
            zh: zh,
            ja: ja,
            ru: ru
        )
    }

    static func ui(
        for languageCode: String,
        fr: String,
        en: String,
        es: String,
        zh: String,
        ja: String,
        ru: String
    ) -> String {
        switch SupportedUILanguage.fromWhisperCode(languageCode) {
        case .fr: return fr
        case .en: return en
        case .es: return es
        case .zh: return zh
        case .ja: return ja
        case .ru: return ru
        }
    }

    static func modelStatusLabel(_ status: ModelStatus, languageCode: String) -> String {
        switch status {
        case .notDownloaded:
            return ui(
                for: languageCode,
                fr: "Non téléchargé",
                en: "Not downloaded",
                es: "No descargado",
                zh: "未下载",
                ja: "未ダウンロード",
                ru: "Не загружено"
            )
        case .downloading(let p):
            let percent = Int(p * 100)
            return ui(
                for: languageCode,
                fr: "Téléchargement \(percent)%",
                en: "Downloading \(percent)%",
                es: "Descargando \(percent)%",
                zh: "下载中 \(percent)%",
                ja: "ダウンロード中 \(percent)%",
                ru: "Загрузка \(percent)%"
            )
        case .loading:
            return ui(
                for: languageCode,
                fr: "Chargement en mémoire…",
                en: "Loading in memory…",
                es: "Cargando en memoria…",
                zh: "正在加载到内存…",
                ja: "メモリに読み込み中…",
                ru: "Загрузка в память…"
            )
        case .ready:
            return ui(
                for: languageCode,
                fr: "Prêt",
                en: "Ready",
                es: "Listo",
                zh: "就绪",
                ja: "準備完了",
                ru: "Готово"
            )
        case .failed(let msg):
            let prefix = ui(
                for: languageCode,
                fr: "Erreur",
                en: "Error",
                es: "Error",
                zh: "错误",
                ja: "エラー",
                ru: "Ошибка"
            )
            return "\(prefix): \(msg)"
        }
    }

    static func hasAdvancedLanguageSupport(_ languageCode: String) -> Bool {
        let normalized = languageCode.lowercased()
        return normalized.hasPrefix("fr")
            || normalized.hasPrefix("en")
            || normalized.hasPrefix("es")
            || normalized.hasPrefix("zh")
            || normalized.hasPrefix("ja")
            || normalized.hasPrefix("ru")
    }

    static func advancedFeaturesNotice(languageCode: String) -> String? {
        if hasAdvancedLanguageSupport(languageCode) {
            return nil
        }
        return ui(
            for: languageCode,
            fr: "Certaines fonctions avancées (snippets contextuels, formatage formel auto) sont optimisées pour FR/EN/ES/ZH/JA/RU.",
            en: "Some advanced features (context snippets, formal auto-formatting) are optimized for FR/EN/ES/ZH/JA/RU.",
            es: "Algunas funciones avanzadas (snippets contextuales, formato formal automático) están optimizadas para FR/EN/ES/ZH/JA/RU.",
            zh: "部分高级功能（上下文片段、正式自动格式化）已针对 FR/EN/ES/ZH/JA/RU 优化。",
            ja: "一部の高度な機能（コンテキストスニペット、フォーマル自動整形）は FR/EN/ES/ZH/JA/RU 向けに最適化されています。",
            ru: "Некоторые расширенные функции (контекстные сниппеты, автоформатирование формального стиля) оптимизированы для FR/EN/ES/ZH/JA/RU."
        )
    }

    static func defaultSnippetTriggers(for kind: SnippetTriggerKind, languageCode: String) -> String {
        let language = SupportedUILanguage.fromWhisperCode(languageCode)
        if let localized = snippetTriggerTable[language]?[kind] {
            return localized
        }
        return snippetTriggerTable[.en]?[kind] ?? ""
    }
}

@MainActor
func t(_ fr: String, _ en: String, _ es: String, _ zh: String, _ ja: String, _ ru: String) -> String {
    L10n.ui(fr, en, es, zh, ja, ru)
}
