import CGio
import Foundation
import VitalsCore

/// A system-tray presence via the freedesktop `StatusNotifierItem` D-Bus
/// protocol — the only route to a tray on GTK4 (the old GtkStatusIcon and
/// libayatana-appindicator are GTK3-only).
///
/// Scope for this version: an icon whose **tooltip carries the live readings**
/// (temperature / CPU / memory / fan) and whose **click opens the window**. A
/// full right-click menu uses the separate `com.canonical.dbusmenu` layout
/// protocol and is a deliberate follow-up.
///
/// Every D-Bus step is guarded: if the session bus, registration, or the
/// StatusNotifierWatcher is unavailable, the tray quietly does nothing and the
/// app keeps running as a normal window. On stock GNOME the icon needs the
/// AppIndicator extension to appear (KDE and most desktops show it natively).
///
/// NOTE: the D-Bus interaction here is compile-verified only — it must be
/// exercised on a real Linux desktop session to confirm runtime behaviour.
final class TrayIcon {

    static let shared = TrayIcon()

    private var connection: OpaquePointer?
    private var nodeInfo: UnsafeMutablePointer<GDBusNodeInfo>?
    private let vtable = UnsafeMutablePointer<GDBusInterfaceVTable>.allocate(capacity: 1)
    private var registered = false

    // Values read back by the get_property callback.
    fileprivate var title = "Vitals"
    fileprivate var tooltip = "Reading sensors…"
    fileprivate var onOpen: () -> Void = {}

    private static let objectPath = "/StatusNotifierItem"
    private static let interface = "org.kde.StatusNotifierItem"

    private static let introspectionXML = """
    <node>
     <interface name="org.kde.StatusNotifierItem">
      <property name="Category" type="s" access="read"/>
      <property name="Id" type="s" access="read"/>
      <property name="Title" type="s" access="read"/>
      <property name="Status" type="s" access="read"/>
      <property name="IconName" type="s" access="read"/>
      <property name="ItemIsMenu" type="b" access="read"/>
      <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
      <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
      <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
      <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
      <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
      <signal name="NewTitle"/>
      <signal name="NewIcon"/>
      <signal name="NewToolTip"/>
      <signal name="NewStatus"><arg name="status" type="s"/></signal>
     </interface>
    </node>
    """

    /// Connects to the session bus and registers the item. Safe to call once.
    func start(onOpen: @escaping () -> Void) {
        guard !registered else { return }
        self.onOpen = onOpen

        guard let conn = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, nil) else { return }
        connection = conn

        guard let node = g_dbus_node_info_new_for_xml(Self.introspectionXML, nil) else { return }
        nodeInfo = node
        guard let iface = g_dbus_node_info_lookup_interface(node, Self.interface) else { return }

        vtable.pointee = GDBusInterfaceVTable(
            method_call: trayMethodCall,
            get_property: trayGetProperty,
            set_property: nil,
            padding: (nil, nil, nil, nil, nil, nil, nil, nil)
        )

        let regID = g_dbus_connection_register_object(
            conn, Self.objectPath, iface, vtable,
            Unmanaged.passRetained(self).toOpaque(), nil, nil
        )
        guard regID != 0 else { return }
        registered = true

        registerWithWatcher(conn)
    }

    /// Tells the StatusNotifierWatcher about us (by our unique bus name; the host
    /// then looks for the item at the conventional `/StatusNotifierItem`).
    private func registerWithWatcher(_ conn: OpaquePointer) {
        guard let unique = g_dbus_connection_get_unique_name(conn) else { return }
        let nameVar = g_variant_new_string(unique)
        var children: [OpaquePointer?] = [nameVar]
        let params = children.withUnsafeMutableBufferPointer { g_variant_new_tuple($0.baseAddress, 1) }
        g_dbus_connection_call(
            conn,
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher",
            "RegisterStatusNotifierItem",
            params, nil, G_DBUS_CALL_FLAGS_NONE, -1, nil, nil, nil
        )
    }

    /// Refreshes the tooltip from the latest readings and notifies the host.
    func update(_ state: DashboardState) {
        tooltip = Self.tooltipText(state)
        guard registered, let conn = connection else { return }
        g_dbus_connection_emit_signal(
            conn, nil, Self.objectPath, Self.interface, "NewToolTip", nil, nil
        )
    }

    fileprivate func property(_ name: String) -> OpaquePointer? {
        switch name {
        case "Category": return g_variant_new_string("Hardware")
        case "Id": return g_variant_new_string("vitals")
        case "Title": return g_variant_new_string(title)
        case "Status": return g_variant_new_string("Active")
        // A stock freedesktop icon so something always shows, even outside our
        // own icon theme.
        case "IconName": return g_variant_new_string("utilities-system-monitor")
        case "ItemIsMenu": return g_variant_new_boolean(0)  // false → click Activates
        case "ToolTip": return tooltipVariant()
        default: return nil
        }
    }

    /// Builds the `(sa(iiay)ss)` ToolTip variant: icon name, (empty) pixmap
    /// array, title, and the readings as the description.
    private func tooltipVariant() -> OpaquePointer? {
        let icon = g_variant_new_string("")
        let pixmaps = g_variant_new_array(g_variant_type_new("(iiay)"), nil, 0)
        let titleVar = g_variant_new_string(title)
        let descVar = g_variant_new_string(tooltip)
        var children: [OpaquePointer?] = [icon, pixmaps, titleVar, descVar]
        return children.withUnsafeMutableBufferPointer { g_variant_new_tuple($0.baseAddress, 4) }
    }

    fileprivate func activate() { onOpen() }

    private static func tooltipText(_ s: DashboardState) -> String {
        guard s.hasLoaded else { return "Reading sensors…" }
        var parts: [String] = []
        parts.append("CPU \(Fmt.temp(s.cpuTempAvg)) · \(Fmt.percent(s.cpuUsage))")
        if let m = s.memory {
            parts.append("Memory \(Fmt.gigabytes(m.used)) / \(Fmt.gigabytes(m.total))")
        }
        if let fan = s.fans.first {
            parts.append(fan.rpm == 0 ? "Fan stopped" : "Fan \(fan.rpm) rpm")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - C callbacks

/// D-Bus method dispatch. Activate / SecondaryActivate / ContextMenu all open
/// the window (there's no menu yet); everything returns an empty reply.
private func trayMethodCall(
    _ connection: OpaquePointer?,
    _ sender: UnsafePointer<CChar>?,
    _ objectPath: UnsafePointer<CChar>?,
    _ interfaceName: UnsafePointer<CChar>?,
    _ methodName: UnsafePointer<CChar>?,
    _ parameters: OpaquePointer?,
    _ invocation: OpaquePointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    if let userData {
        let tray = Unmanaged<TrayIcon>.fromOpaque(userData).takeUnretainedValue()
        switch methodName.map({ String(cString: $0) }) {
        case "Activate", "SecondaryActivate", "ContextMenu": tray.activate()
        default: break
        }
    }
    g_dbus_method_invocation_return_value(invocation, nil)
}

private func trayGetProperty(
    _ connection: OpaquePointer?,
    _ sender: UnsafePointer<CChar>?,
    _ objectPath: UnsafePointer<CChar>?,
    _ interfaceName: UnsafePointer<CChar>?,
    _ propertyName: UnsafePointer<CChar>?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<GError>?>?,
    _ userData: UnsafeMutableRawPointer?
) -> OpaquePointer? {
    guard let userData, let propertyName else { return nil }
    let tray = Unmanaged<TrayIcon>.fromOpaque(userData).takeUnretainedValue()
    return tray.property(String(cString: propertyName))
}
