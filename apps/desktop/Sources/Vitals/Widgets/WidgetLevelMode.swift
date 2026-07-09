import Foundation

/// Where the desktop widgets sit in the window stack. Persisted by raw value.
enum WidgetLevelMode: String, CaseIterable, Identifiable {
    /// Above every window — always visible, always interactive.
    case floating
    /// On the desktop, behind app windows but *above* the desktop icons —
    /// interactive at all times, at the cost of covering files that land under
    /// a widget. The default.
    case desktop
    /// Part of the desktop itself, *behind* the icons: files and screenshots
    /// always render on top and clicks pass straight through to them. To
    /// arrange, bring Vitals forward — widgets surface (and become draggable)
    /// while Vitals is the active app, then sink back.
    case behindIcons

    var id: String { rawValue }

    var label: String {
        switch self {
        case .floating: return "Above windows"
        case .desktop: return "On desktop"
        case .behindIcons: return "Behind icons"
        }
    }

    /// The explanation Settings shows for the selected mode.
    var caption: String {
        switch self {
        case .floating:
            return "Widgets float above every window."
        case .desktop:
            return "Widgets sit on the desktop, behind your windows but over desktop icons."
        case .behindIcons:
            return "Widgets are part of the desktop: files and screenshots stay on top, clicks pass through. Bring Vitals forward to arrange them."
        }
    }
}
