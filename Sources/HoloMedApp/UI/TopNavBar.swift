import SwiftUI

public struct TopNavBar: View {
    @ObservedObject var appState: AppState
    @Binding var showSettingsSheet: Bool

    public var body: some View {
        HStack(spacing: 12) {
            // Mode Switcher Pill
            HStack(spacing: 4) {
                ForEach(AppMode.allCases) { mode in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            appState.setMode(mode)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 11, weight: .bold))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            appState.activeMode == mode
                                ? (mode == .pathology ? Color.red : Color.blue)
                                : Color.clear
                        )
                        .foregroundColor(appState.activeMode == mode ? .white : .white.opacity(0.7))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))

            Spacer()

            // Comprehension Level Menu
            Menu {
                ForEach(ComprehensionLevel.allCases) { level in
                    Button(action: {
                        appState.comprehensionLevel = level
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(level.title)
                                Text(level.subtitle).font(.caption)
                            }
                            if appState.comprehensionLevel == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .bold))
                    Text(appState.comprehensionLevel.title)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.15))
                .foregroundColor(.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }

            // Provider Settings Button
            Button(action: {
                showSettingsSheet = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
        )
    }
}
