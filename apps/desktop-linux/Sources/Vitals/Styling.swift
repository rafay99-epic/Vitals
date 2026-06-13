import CAdw

/// App-wide appearance. The macOS Vitals reads as a dark, glassy panel; libadwaita
/// can't reproduce the materials, but forcing the dark color scheme gets the same
/// overall feel and — crucially — makes the `.card()` surfaces visibly elevated
/// (on the default light theme they're nearly invisible).
enum Theme {

    /// Force dark regardless of the desktop's system preference.
    static func applyDark() {
        adw_style_manager_set_color_scheme(adw_style_manager_get_default(), ADW_COLOR_SCHEME_FORCE_DARK)
    }

    /// Loaded once globally (via `.css`). A few semantic classes that nudge the
    /// hierarchy toward the macOS dashboard — applied with `.style("…")`.
    static let css = """
    .vitals-stat-title { font-size: 11px; font-weight: 700; letter-spacing: 0.7px; opacity: 0.55; }
    .vitals-hero { font-size: 28px; font-weight: 800; }
    .vitals-section { font-size: 15px; font-weight: 700; }
    .vitals-sub { opacity: 0.55; }
    .vitals-card { padding: 6px; }
    """
}
