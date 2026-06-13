import Adwaita
import VitalsCore

/// Vitals for Linux — a native GTK4/libadwaita hardware monitor.
///
/// Monitoring only: the Dashboard plus a menu-bar/tray item. Cleanup,
/// uninstall, and app management stay exclusive to the macOS build by design.
@main
struct VitalsApp: App {

    let id = BuildInfo.appID
    var app: GTUIApp!

    var scene: Scene {
        Window(id: "main") { _ in
            DashboardView(app: app)
        }
        .title(BuildInfo.displayName)
        .defaultSize(width: 820, height: 640)
    }
}
