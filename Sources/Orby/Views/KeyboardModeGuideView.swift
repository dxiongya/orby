import SwiftUI

struct KeyboardModeGuideView: View {
    @State private var currentStep = 0
    var onFinish: () -> Void

    private let steps: [(icon: String, title: String, subtitle: String, keys: String?, detail: String)] = [
        (
            icon: "keyboard.fill",
            title: "Keyboard Mode",
            subtitle: "Navigate Orby entirely by keyboard",
            keys: nil,
            detail: "Orby appears at the center of your screen.\nNo mouse needed — everything is\ncontrolled with keys."
        ),
        (
            icon: "arrow.left.arrow.right",
            title: "Navigate Apps",
            subtitle: "Cycle focus with arrow keys",
            keys: "← →",
            detail: "Press ← or → to move focus between apps.\nThe focused app enlarges and\nneighboring apps spread apart."
        ),
        (
            icon: "play.circle.fill",
            title: "Activate",
            subtitle: "Space to switch or expand",
            keys: "Space",
            detail: "Single-window app → instantly switches to it.\nMulti-window app → expands its windows\ninto sub-window mode."
        ),
        (
            icon: "textformat.123",
            title: "Number Shortcuts",
            subtitle: "Jump directly to nearby apps",
            keys: "1 – 6",
            detail: "1, 2, 3 → left neighbors (nearest to farthest)\n4, 5, 6 → right neighbors (nearest to farthest)\nEach app shows its number badge."
        ),
        (
            icon: "square.on.square",
            title: "Sub-window Mode",
            subtitle: "Same controls, for windows",
            keys: "← → Space 1-6",
            detail: "After expanding a multi-window app:\n← → cycles between windows,\nSpace activates, 1-6 jumps to neighbors."
        ),
        (
            icon: "arrow.uturn.backward.circle.fill",
            title: "Go Back",
            subtitle: "Escape exits layer by layer",
            keys: "ESC",
            detail: "In sub-window mode → back to main apps.\nIn main apps → close Orby.\nJust keep pressing ESC to exit."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                }

                Text("Keyboard Mode Guide")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color.orange : Color.primary.opacity(0.15))
                            .frame(width: 6, height: 6)
                            .scaleEffect(i == currentStep ? 1.2 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentStep)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Card
            let step = steps[currentStep]

            VStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.15), Color.orange.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: step.icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.top, 4)

                // Title & subtitle
                VStack(spacing: 4) {
                    Text(step.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text(step.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Key badge
                if let keys = step.keys {
                    HStack(spacing: 6) {
                        ForEach(keys.components(separatedBy: " ").filter { !$0.isEmpty }, id: \.self) { key in
                            Text(key)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, key.count > 2 ? 12 : 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                                )
                        }
                    }
                }

                // Detail text
                Text(step.detail)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
            .id(currentStep)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            currentStep -= 1
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .frame(width: 80, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            currentStep += 1
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 90, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onFinish()
                    } label: {
                        Text("Got It")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 100, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Skip
            if currentStep < steps.count - 1 {
                Button("Skip") {
                    onFinish()
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 380, height: 460)
    }
}
