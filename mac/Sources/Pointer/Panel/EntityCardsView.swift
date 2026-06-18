import SwiftUI

/// Structured actionable results — Open, Directions, Reviews — not prose only.
struct EntityCardsView: View {
    let entities: [PanelEntity]
    let onAction: (PanelEntity, PanelEntity.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(entities) { entity in
                entityCard(entity)
            }
        }
    }

    private func entityCard(_ entity: PanelEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("#\(entity.index)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if let subtitle = entity.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(entity.availableActions, id: \.rawValue) { action in
                    Button(actionLabel(action)) {
                        onAction(entity, action)
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.08))
        )
    }

    private func actionLabel(_ action: PanelEntity.Action) -> String {
        switch action {
        case .open: "Open"
        case .reviews: "Reviews"
        case .directions: "Directions"
        case .copy: "Copy"
        }
    }
}
