//
//  ContentView.swift
//  Beet
//
//  Created by Ted Schultz on 5/14/26.
//

import SwiftUI

private enum PlayRoute: Hashable {
    case modeSelect
    case singleMaze
    case splitScreen
}

struct ContentView: View {
    @State private var route: PlayRoute = .modeSelect

    var body: some View {
        Group {
            switch route {
            case .modeSelect:
                PlayModeSelectView(
                    onSingle: { route = .singleMaze },
                    onSplit: { route = .splitScreen }
                )
            case .singleMaze:
                BeetGameView(onMainMenu: { route = .modeSelect })
            case .splitScreen:
                DualBeetGameView(onMainMenu: { route = .modeSelect })
            }
        }
        .animation(.easeInOut(duration: 0.22), value: route)
    }
}

// MARK: - Mode picker

private struct PlayModeSelectView: View {
    let onSingle: () -> Void
    let onSplit: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.11)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Beet")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Ledges")
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.bottom, 8)

                Text("How do you want to play?")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                VStack(spacing: 14) {
                    Button {
                        onSingle()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("One maze")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                            Text("Full screen, single lane.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.22, green: 0.55, blue: 0.34))

                    Button {
                        onSplit()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Split screen")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                            Text("Two mazes side by side. One wall ends the run; steps add together.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .padding(.top, 48)
        }
    }
}

#Preview {
    ContentView()
}
