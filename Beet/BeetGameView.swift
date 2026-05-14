//
//  BeetGameView.swift
//  Beet
//
//  SwiftUI shell around the SpriteKit ledge game.
//

import SpriteKit
import SwiftUI

@MainActor
final class BeetGameController: ObservableObject, LedgesGameSceneDelegate {
    let scene: LedgesGameScene

    @Published private(set) var tilesPassed = 0
    @Published private(set) var runSeconds: CGFloat = 0
    @Published private(set) var isGameOver = false

    init(mazePhase: CGFloat = 0) {
        scene = LedgesGameScene(size: .zero, mazePhase: mazePhase)
        scene.gameDelegate = self
    }

    func ledgesScene(_ scene: LedgesGameScene, didUpdate tilesPassed: Int, seconds: CGFloat) {
        self.tilesPassed = tilesPassed
        self.runSeconds = seconds
    }

    func ledgesSceneGameOver(_ scene: LedgesGameScene) {
        isGameOver = true
    }

    func layoutScene(size: CGSize) {
        scene.layoutScene(size: size)
    }

    func jump() {
        scene.jump()
    }

    func restart() {
        isGameOver = false
        scene.restart()
    }

    func setScenePaused(_ paused: Bool) {
        scene.isPaused = paused
    }
}

// MARK: - Time formatting

private func timeString(_ t: CGFloat) -> String {
    let s = max(0, Int(t))
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Single lane (SpriteKit + HUD)

struct BeetLaneView: View {
    @ObservedObject var game: BeetGameController
    var laneCaption: String
    /// When false, taps do not jump (dual session ended on either side).
    var jumpEnabled: Bool
    var showLocalGameOver: Bool
    /// In dual mode the parent shows combined steps; hide the large per-lane step line.
    var showTopLaneHUD: Bool
    /// Shown on the game-over card (e.g. return to mode picker).
    var onMainMenu: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                SpriteView(scene: game.scene, options: [.allowsTransparency])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack {
                    if showTopLaneHUD {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(laneCaption)
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("Steps \(game.tilesPassed)")
                                    .font(.system(.title3, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.95))
                            }
                            Spacer()
                            Text(timeString(game.runSeconds))
                                .font(.system(.title3, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                    if !showTopLaneHUD {
                        Text(laneCaption)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.top, 8)
                        Text("This lane: \(game.tilesPassed)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Text(showTopLaneHUD ? "Tap anywhere to jump up to the next ledge" : "Tap this side to jump")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 28)
                }
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { game.jump() }
                    .allowsHitTesting(jumpEnabled)

                if showLocalGameOver, game.isGameOver {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Hit the wall")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Steps cleared: \(game.tilesPassed)")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Button("Play again") {
                            game.restart()
                        }
                        .buttonStyle(.borderedProminent)
                        if let onMainMenu {
                            Button("Change mode") {
                                onMainMenu()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .onAppear { game.layoutScene(size: size) }
            .onChange(of: geo.size) { _, new in game.layoutScene(size: new) }
        }
    }
}

// MARK: - Single-player shell

struct BeetGameView: View {
    private let laneCaption: String
    private let onMainMenu: (() -> Void)?
    @StateObject private var game: BeetGameController

    init(mazePhase: CGFloat = 0, laneCaption: String = "Ledges", onMainMenu: (() -> Void)? = nil) {
        self.laneCaption = laneCaption
        self.onMainMenu = onMainMenu
        _game = StateObject(wrappedValue: BeetGameController(mazePhase: mazePhase))
    }

    var body: some View {
        BeetLaneView(
            game: game,
            laneCaption: laneCaption,
            jumpEnabled: !game.isGameOver,
            showLocalGameOver: true,
            showTopLaneHUD: true,
            onMainMenu: onMainMenu
        )
    }
}

// MARK: - Dual lanes (shared session)

struct DualBeetGameView: View {
    var onMainMenu: (() -> Void)? = nil

    @StateObject private var leftGame = BeetGameController(mazePhase: 0)
    @StateObject private var rightGame = BeetGameController(mazePhase: .pi * 1.37 + 0.6)

    private var sessionOver: Bool { leftGame.isGameOver || rightGame.isGameOver }
    private var totalSteps: Int { leftGame.tilesPassed + rightGame.tilesPassed }
    private var sessionTime: CGFloat { max(leftGame.runSeconds, rightGame.runSeconds) }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                BeetLaneView(
                    game: leftGame,
                    laneCaption: "Left maze",
                    jumpEnabled: !sessionOver,
                    showLocalGameOver: false,
                    showTopLaneHUD: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1)

                BeetLaneView(
                    game: rightGame,
                    laneCaption: "Right maze",
                    jumpEnabled: !sessionOver,
                    showLocalGameOver: false,
                    showTopLaneHUD: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Both mazes")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Total steps \(totalSteps)")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    Spacer()
                    Text(timeString(sessionTime))
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                Spacer()
            }
            .allowsHitTesting(false)

            if sessionOver {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Hit the wall")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Total steps: \(totalSteps)")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Left \(leftGame.tilesPassed) · Right \(rightGame.tilesPassed)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                    Button("Play again") {
                        leftGame.restart()
                        rightGame.restart()
                    }
                    .buttonStyle(.borderedProminent)
                    if let onMainMenu {
                        Button("Change mode") {
                            onMainMenu()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .onChange(of: sessionOver) { _, over in
            if over {
                leftGame.setScenePaused(true)
                rightGame.setScenePaused(true)
            }
        }
    }
}

#Preview("Single") {
    BeetGameView()
}

#Preview("Dual") {
    DualBeetGameView()
}
