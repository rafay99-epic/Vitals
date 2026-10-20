import SwiftUI

/// The Cleanup section: Quick and Deep cache sweeps and per-project Developer
/// junk behind one picker. Pages swap in place, so window geometry never changes.
struct CleanupView: View {
    @Bindable var model: CleanupModel
    /// Persisted so the chosen page sticks across launches. A stored page that
    /// no longer exists falls back to Quick.
    @AppStorage("cleanupPage") private var page: CleanupPage = .quick

    var body: some View {
        VStack(spacing: 0) {
            picker
            Divider()
                .opacity(0.5)
            ZStack {
                switch page {
                case .quick:
                    CleanupClassicPage(model: model, depth: .quick)
                        .transition(.opacity)
                case .deep:
                    CleanupClassicPage(model: model, depth: .deep)
                        .transition(.opacity)
                case .developer:
                    CleanupDeveloperPage(model: model)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: page)
        }
    }

    private var picker: some View {
        HStack {
            // A pull-down menu so the label shows the current page with its icon.
            Picker(selection: $page) {
                ForEach(CleanupPage.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            } label: {
                Label(page.title, systemImage: page.symbol)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(model.isCleaning || model.isDevCleaning)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
