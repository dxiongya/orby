import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0
    var onFinish: () -> Void

    private let steps: [(icon: String, title: String, subtitle: String, keys: String?, detail: String)] = [
        (
            icon: "circle.grid.3x3.fill",
            title: "Quick Start",
            subtitle: "Summon your apps in a circle",
            keys: "⌥ Tab",
            detail: "Press the hotkey to open Orby.\nAll running apps appear around your cursor.\nClick any app to switch instantly."
        ),
        (
            icon: "cursorarrow.and.square.on.square.dashed",
            title: "Navigate & Preview",
            subtitle: "Hover to explore windows",
            keys: nil,
            detail: "Hover an app to expand its windows.\nA live preview appears when you pause.\nPinch to zoom the preview."
        ),
        (
            icon: "bolt.fill",
            title: "Quick Launch",
            subtitle: "One key to reach any app",
            keys: "⌥ 1–9",
            detail: "Right-click any app or window bubble.\nBind it to ⌥+Number for instant access.\nWorks globally — even outside Orby."
        ),
        (
            icon: "option",
            title: "Reveal Names",
            subtitle: "See all window titles at once",
            keys: "Hold ⌥",
            detail: "Hold the Option key while Orby is open.\nAll sub-app window names appear instantly.\nRelease to hide them again."
        ),
        (
            icon: "tag.fill",
            title: "Tag Your Apps",
            subtitle: "Color-coded labels for fast recognition",
            keys: nil,
            detail: "Right-click any bubble and choose a tag.\nOr select \"New Tag...\" to create one inline.\nTags persist across sessions."
        ),
        (
            icon: "xmark.circle.fill",
            title: "Close Mode",
            subtitle: "Quickly quit apps or close windows",
            keys: "Long Press",
            detail: "Long-press on any bubble to enter close mode.\nBubbles start wobbling — tap to close.\nPress ESC to exit close mode."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Logo + Progress dots
            HStack(spacing: 10) {
                Group {
                    Image("OrbyLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .frame(width: 28, height: 28)

                Text("Orby")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color.accentColor : Color.primary.opacity(0.15))
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
                                colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: step.icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.accentColor)
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
                    Text(keys)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        )
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
                                .fill(Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onFinish()
                    } label: {
                        Text("Get Started")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 110, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor)
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
        .frame(width: 380, height: 440)
    }
}
