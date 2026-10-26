import SwiftUI

/// The app's capsule segmented control: a sliding `.quaternary` indicator in a
/// faint capsule. `selection` may match no option (nothing is highlighted).
struct CapsuleSegments<Value: Hashable>: View {
    let options: [Value]
    let selection: Value?
    let title: (Value) -> String
    let onSelect: (Value) -> Void
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { onSelect(option) }
                } label: {
                    Text(title(option))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == option ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .background {
                    if selection == option {
                        Capsule().fill(.quaternary).matchedGeometryEffect(id: "segment", in: indicator)
                    }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }
}
