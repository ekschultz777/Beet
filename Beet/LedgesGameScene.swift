//
//  LedgesGameScene.swift
//  Beet
//
//  SpriteKit: stepped maze — each column’s ledge steps from the previous (never level), with
//  beat-sized deltas so maps can later follow music / tap timing.
//

import SpriteKit

protocol LedgesGameSceneDelegate: AnyObject {
    func ledgesScene(_ scene: LedgesGameScene, didUpdate tilesPassed: Int, seconds: CGFloat)
    func ledgesSceneGameOver(_ scene: LedgesGameScene)
}

/// Model space: origin top-left, +Y increases downward.
final class LedgesGameScene: SKScene {
    weak var gameDelegate: LedgesGameSceneDelegate?

    private struct Column: Identifiable {
        let id = UUID()
        var leadX: CGFloat
        let width: CGFloat
        let ceilingY: CGFloat
        let floorY: CGFloat
        let index: Int
    }

    private let mazeFill = SKColor(red: 0.22, green: 0.55, blue: 0.34, alpha: 1)
    private let mazeStroke = SKColor(red: 0.1, green: 0.32, blue: 0.2, alpha: 1)
    private let mazeNode = SKShapeNode()
    private let ball = SKShapeNode(circleOfRadius: 18)

    private var columns: [Column] = []
    private var ballY: CGFloat = 0
    private var ballVy: CGFloat = 0
    private var runTime: CGFloat = 0
    private var passedCount = 0
    private var layoutSize: CGSize = .zero
    private var lastTick: TimeInterval?
    private var isGameOver = false
    private var passedIDs = Set<UUID>()
    /// No crush checks until the run has advanced (avoids false game-over on spawn).
    private var crushReadyTime: CGFloat = 0

    private let ballR: CGFloat = 18
    private let gravity: CGFloat = 2000
    private let jumpImpulse: CGFloat = -560
    private let scrollSpeed: CGFloat = 120
    private let minAirGap: CGFloat = 110
    private let spawnAhead: CGFloat = 360
    /// Narrow columns are impossible to thread; keep comfortably wider than the ball.
    private let minColumnWidth: CGFloat = 80
    private let maxColumnWidth: CGFloat = 132
    /// Neighbor ledges never share height; step size is in the range taps will later align to beats.
    private let minFloorStep: CGFloat = 32
    private let maxFloorStep: CGFloat = 54
    /// Shifts width / floor phases so two lanes can share rules but different mazes.
    private let mazePhase: CGFloat
    /// Tempo for rhythm-aligned column widths (scroll distance per beat at `scrollSpeed`). Fixed for the run.
    private let bpm: CGFloat

    private func ballX() -> CGFloat { layoutSize.width * 0.5 }

    /// World-space points the maze scrolls in one musical beat at the current BPM.
    private func scrollPointsPerBeat() -> CGFloat {
        let clampedBpm = max(40, min(240, bpm))
        return scrollSpeed * 60 / clampedBpm
    }

    /// Width quantization grid: whole beats, halved as needed until a column can fit `maxColumnWidth`.
    private func columnWidthGridUnit() -> CGFloat {
        let beat = scrollPointsPerBeat()
        var g = beat
        while g > maxColumnWidth {
            g /= 2
        }
        return max(1, g)
    }

    /// Snaps procedural width to a multiple of the beat grid so columns line up with tempo.
    private func quantizeColumnWidth(_ raw: CGFloat) -> CGFloat {
        let q = columnWidthGridUnit()
        let rawClamped = min(maxColumnWidth, max(minColumnWidth, raw))
        var k = (rawClamped / q).rounded(.toNearestOrAwayFromZero)
        k = max(1, k)
        var w = k * q
        if w < minColumnWidth {
            k = ceil(minColumnWidth / q)
            w = max(minColumnWidth, k * q)
        }
        if w > maxColumnWidth {
            k = floor(maxColumnWidth / q)
            k = max(1, k)
            w = k * q
        }
        return min(maxColumnWidth, max(minColumnWidth, w))
    }

    private func columnWidth(forIndex i: Int) -> CGFloat {
        let gi = CGFloat(i)
        let u = 0.5
            + 0.5 * sin(gi * 1.73 + sin(gi * 0.37 + mazePhase * 0.41) * 2.1 + mazePhase * 0.51)
        let raw = minColumnWidth + (maxColumnWidth - minColumnWidth) * min(1, max(0, u))
        return quantizeColumnWidth(raw)
    }

    init(size: CGSize, mazePhase: CGFloat = 0, bpm: CGFloat = 120) {
        self.mazePhase = mazePhase
        self.bpm = max(40, min(240, bpm))
        super.init(size: size)
        anchorPoint = .zero
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1)
        isPaused = false

        mazeNode.fillColor = mazeFill
        mazeNode.strokeColor = mazeStroke
        mazeNode.lineWidth = 1.25
        mazeNode.zPosition = 0

        ball.fillColor = SKColor(red: 0.45, green: 0.88, blue: 1, alpha: 1)
        ball.strokeColor = .clear
        ball.zPosition = 10

        addChild(mazeNode)
        addChild(ball)
    }

    required init?(coder aDecoder: NSCoder) {
        self.mazePhase = 0
        self.bpm = 120
        fatalError("init(coder:) has not been implemented")
    }

    func layoutScene(size: CGSize) {
        guard size.width > 40, size.height > 40 else { return }
        if layoutSize != size {
            layoutSize = size
            self.size = size
            isPaused = false
            restart()
        }
    }

    func restart() {
        columns.removeAll()
        passedIDs.removeAll()
        passedCount = 0
        runTime = 0
        lastTick = nil
        isGameOver = false
        ballVy = 0
        crushReadyTime = 0.45

        guard layoutSize.height > 40, layoutSize.width > 40 else { return }

        let bx = ballX()
        let targetColumns = 28
        var pending: [(lead: CGFloat, width: CGFloat, index: Int)] = []
        var rightEdge = layoutSize.width + spawnAhead
        for i in 0..<targetColumns {
            let cw = columnWidth(forIndex: -i)
            let lead = rightEdge - cw
            pending.append((lead, cw, -i))
            rightEdge = lead
        }

        if let leftmost = pending.min(by: { $0.lead < $1.lead }) {
            let dx = bx - leftmost.width * 0.38 - leftmost.lead
            pending = pending.map { ($0.lead + dx, $0.width, $0.index) }
        }

        let ordered = pending.sorted { $0.lead < $1.lead }
        var prevFloor: CGFloat?
        columns = ordered.enumerated().map { pair in
            let (spatial, p) = pair
            let (c, f) = ceilingAndFloor(previousFloor: prevFloor, spatialIndex: spatial, columnIndex: p.index)
            prevFloor = f
            return Column(leadX: p.lead, width: p.width, ceilingY: c, floorY: f, index: p.index)
        }

        snapBallToFloor(ballX: bx)
        rebuildMaze()
        syncBall()
        notifyHud()
        isPaused = false
    }

    func jump() {
        guard !isGameOver, layoutSize.width > 40 else { return }
        ballVy = jumpImpulse
    }

    private func floorBounds() -> (lo: CGFloat, hi: CGFloat) {
        let h = layoutSize.height
        let margin = ballR + 28
        let lo = margin + minAirGap + ballR
        let hi = h - margin
        return (lo, hi)
    }

    /// `previousFloor == nil` → first column along the path. Otherwise always ≥ `minFloorStep` from `previousFloor`.
    private func ceilingAndFloor(previousFloor: CGFloat?, spatialIndex: Int, columnIndex: Int) -> (CGFloat, CGFloat) {
        let margin = ballR + 28
        let (lo, hi) = floorBounds()
        let floorY: CGFloat
        if let prev = previousFloor {
            floorY = nextFloorAfter(previous: prev, spatialIndex: spatialIndex, columnIndex: columnIndex, lo: lo, hi: hi)
        } else {
            var f = layoutSize.height * 0.56
                + sin(CGFloat(columnIndex) * 0.37 + mazePhase * 2.17) * 18
            f = min(hi, max(lo, f))
            floorY = f
        }
        let ceilingY = max(margin, floorY - minAirGap - ballR * 0.5)
        return (ceilingY, floorY)
    }

    private func nextFloorAfter(previous prev: CGFloat, spatialIndex: Int, columnIndex: Int, lo: CGFloat, hi: CGFloat) -> CGFloat {
        let u = 0.5
            + 0.5 * sin(
                CGFloat(columnIndex) * 1.919 + CGFloat(spatialIndex) * 0.71 + mazePhase * 0.83
            )
        let magnitude = minFloorStep + CGFloat(u) * (maxFloorStep - minFloorStep)
        // Even spatial index → ledge goes up (smaller Y); odd → down. Never flat vs previous.
        let upward = spatialIndex % 2 == 0
        let delta: CGFloat = upward ? -magnitude : magnitude
        var next = prev + delta
        next = min(hi, max(lo, next))
        if abs(next - prev) < minFloorStep {
            let bump: CGFloat = next >= prev ? minFloorStep : -minFloorStep
            next = prev + bump
            next = min(hi, max(lo, next))
        }
        if abs(next - prev) < minFloorStep {
            let bump: CGFloat = prev > (lo + hi) * 0.5 ? -minFloorStep : minFloorStep
            next = prev + bump
            next = min(hi, max(lo, next))
        }
        return next
    }

    private func snapBallToFloor(ballX bx: CGFloat) {
        guard let band = verticalBand(atBallX: bx) else {
            ballY = layoutSize.height * 0.65
            ballVy = 0
            return
        }
        ballY = band.floor - ballR
        ballVy = 0
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        guard !isGameOver, layoutSize.width > 40 else { return }

        let dt: CGFloat
        if let t0 = lastTick {
            dt = CGFloat(currentTime - t0)
        } else {
            dt = 1 / 60
        }
        lastTick = currentTime
        let dtClamped = min(max(dt, 0), 1 / 30)

        runTime += dtClamped
        if crushReadyTime > 0 {
            crushReadyTime -= dtClamped
        }

        scroll(dt: dtClamped)
        pruneAndSpawn()
        integrate(dt: dtClamped)

        // Leading-face crush must run *before* clampToCorridor; otherwise the clamp
        // always pulls the ball into the legal band and crush never triggers.
        if crushReadyTime <= 0, checkCrush(ballX: ballX()) {
            isGameOver = true
            notifyHud()
            gameDelegate?.ledgesSceneGameOver(self)
            return
        }
        clampToCorridor(ballX: ballX())

        countPasses(ballX: ballX())

        rebuildMaze()
        syncBall()
        notifyHud()
    }

    private func scroll(dt: CGFloat) {
        let dx = scrollSpeed * dt
        for i in columns.indices { columns[i].leadX -= dx }
    }

    private func pruneAndSpawn() {
        columns.removeAll { col in
            col.leadX + col.width < -100
        }
        guard let rightmost = columns.max(by: { $0.leadX + $0.width < $1.leadX + $1.width }) else { return }
        let rightEdge = rightmost.leadX + rightmost.width
        if rightEdge < layoutSize.width + spawnAhead {
            let nextI = (columns.map(\.index).max() ?? 0) + 1
            let cw = columnWidth(forIndex: nextI)
            let prevFloor = rightmost.floorY
            let spatial = columns.count
            let (c, f) = ceilingAndFloor(previousFloor: prevFloor, spatialIndex: spatial, columnIndex: nextI)
            columns.append(Column(leadX: rightEdge, width: cw, ceilingY: c, floorY: f, index: nextI))
        }
    }

    private func integrate(dt: CGFloat) {
        ballVy += gravity * dt
        ballY += ballVy * dt
    }

    private func clampToCorridor(ballX bx: CGFloat) {
        guard let band = verticalBand(atBallX: bx) else { return }
        let minY = band.ceiling + ballR
        let maxY = band.floor - ballR
        guard maxY >= minY else { return }
        if ballY < minY {
            ballY = minY
            ballVy = min(0, ballVy)
        } else if ballY > maxY {
            ballY = maxY
            ballVy = max(0, ballVy)
        }
        if ballY >= maxY - 0.5 {
            ballVy = min(ballVy, 0)
        }
    }

    private func verticalBand(atBallX bx: CGFloat) -> (ceiling: CGFloat, floor: CGFloat)? {
        let sorted = columns.sorted { $0.leadX < $1.leadX }
        guard let first = sorted.first else { return nil }
        if bx <= first.leadX { return (first.ceilingY, first.floorY) }
        for j in 0..<sorted.count {
            let col = sorted[j]
            if bx <= col.leadX + col.width {
                return (col.ceilingY, col.floorY)
            }
            if j + 1 < sorted.count {
                let n = sorted[j + 1]
                if bx < n.leadX {
                    let span = max(1, n.leadX - (col.leadX + col.width))
                    let u = (bx - (col.leadX + col.width)) / span
                    let c = col.ceilingY + (n.ceilingY - col.ceilingY) * u
                    let f = col.floorY + (n.floorY - col.floorY) * u
                    return (c, f)
                }
            }
        }
        guard let last = sorted.last else { return nil }
        return (last.ceilingY, last.floorY)
    }

    /// Shortest distance from a point to a segment (model space).
    private func distancePointToSegment(
        px: CGFloat, py: CGFloat,
        x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat
    ) -> CGFloat {
        let vx = x2 - x1
        let vy = y2 - y1
        let lenSq = vx * vx + vy * vy
        if lenSq < 1e-4 {
            return hypot(px - x1, py - y1)
        }
        var t = ((px - x1) * vx + (py - y1) * vy) / lenSq
        t = min(1, max(0, t))
        let qx = x1 + t * vx
        let qy = y1 + t * vy
        return hypot(px - qx, py - qy)
    }

    /// Game over when the ball touches either vertical leading face of a column:
    /// upper slab [0, ceilingY] and lower slab [floorY, height] at x == leadX.
    /// The air gap (ceilingY…floorY) is omitted on that line, so threading the gap is safe.
    private func checkCrush(ballX bx: CGFloat) -> Bool {
        let h = layoutSize.height
        guard h > 40 else { return false }
        let px = bx
        let py = ballY

        for col in columns {
            let xFace = col.leadX
            // Upper leading face: solid from top of world down to ceiling line.
            let dUpper = distancePointToSegment(
                px: px, py: py,
                x1: xFace, y1: 0, x2: xFace, y2: col.ceilingY
            )
            if dUpper <= ballR {
                return true
            }
            // Lower leading face: solid from floor line to bottom of world.
            let dLower = distancePointToSegment(
                px: px, py: py,
                x1: xFace, y1: col.floorY, x2: xFace, y2: h
            )
            if dLower <= ballR {
                return true
            }
        }
        return false
    }

    private func countPasses(ballX bx: CGFloat) {
        for col in columns {
            guard !passedIDs.contains(col.id) else { continue }
            if col.leadX + col.width < bx - ballR * 0.15 {
                passedIDs.insert(col.id)
                passedCount += 1
            }
        }
    }

    private func skY(_ modelY: CGFloat) -> CGFloat { layoutSize.height - modelY }

    private func rebuildMaze() {
        let h = layoutSize.height
        let path = CGMutablePath()
        let sorted = columns.sorted { $0.leadX < $1.leadX }
        func addModelRect(_ r: CGRect) {
            let rr = CGRect(x: r.minX, y: skY(r.maxY), width: r.width, height: r.height)
            path.addRect(rr)
        }
        for col in sorted {
            addModelRect(CGRect(x: col.leadX, y: 0, width: col.width, height: max(0, col.ceilingY)))
            addModelRect(CGRect(x: col.leadX, y: col.floorY, width: col.width, height: max(0, h - col.floorY)))
        }
        if sorted.count >= 2 {
            for i in 0..<(sorted.count - 1) {
                let a = sorted[i]
                let b = sorted[i + 1]
                let x0 = a.leadX + a.width
                let x1 = b.leadX
                guard x1 > x0 + 1 else { continue }
                let topH = min(a.ceilingY, b.ceilingY)
                addModelRect(CGRect(x: x0, y: 0, width: x1 - x0, height: max(0, topH)))
                let botY = max(a.floorY, b.floorY)
                addModelRect(CGRect(x: x0, y: botY, width: x1 - x0, height: max(0, h - botY)))
            }
        }
        mazeNode.path = path
    }

    private func syncBall() {
        ball.position = CGPoint(x: ballX(), y: skY(ballY))
    }

    private func notifyHud() {
        gameDelegate?.ledgesScene(self, didUpdate: passedCount, seconds: runTime)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        let wasReady = layoutSize.width > 40 && layoutSize.height > 40
        layoutSize = size
        if !wasReady, size.width > 40, size.height > 40 {
            self.size = size
            isPaused = false
            restart()
        } else if wasReady {
            rebuildMaze()
            syncBall()
        }
    }
}
