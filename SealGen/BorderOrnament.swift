import CoreGraphics

enum BorderOrnament {
    /// How far the ornament reaches inward, in millimetres. Text that fills the face stays clear of it.
    static func reachMM(_ project: StampProject) -> Double {
        let weight = project.borderMM
        guard weight > 0.05 else { return 0 }
        let factor: Double
        switch project.borderStyle {
        case .line: factor = 1
        case .double: factor = 3.3
        case .bracket: factor = 2.2
        case .meander: factor = 4.8
        case .keyCorner: factor = 3.4
        case .scallop: factor = 3.3
        case .sea: factor = 4.6
        }
        let cap = min(project.widthMM, project.heightMM) * 0.26
        return min(weight * factor, cap)
    }

    static func draw(project: StampProject, path: CGPath, ctx: CGContext, width: Int, height: Int) {
        guard project.borderMM > 0.05 else { return }
        let weight = max(1.05, CGFloat(project.borderMM / project.widthMM) * CGFloat(width))
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        let round = project.shape == .circle || project.shape == .ellipse
        switch project.borderStyle {
        case .line:
            strokeRim(ctx, path: path, weight: weight)
        case .double:
            strokeRim(ctx, path: path, weight: weight * 0.82)
            strokeParallel(ctx, path: path, width: width, height: height, inset: weight * 2.5, line: weight * 0.82)
        case .bracket:
            if round { strokeRim(ctx, path: path, weight: weight * 0.75) }
            strokeBracket(ctx, width: width, height: height, weight: weight, round: round)
        case .meander:
            if round { strokeRim(ctx, path: path, weight: weight * 0.72) }
            strokeMeander(ctx, project: project, width: width, height: height, weight: weight, round: round)
        case .keyCorner:
            strokeRim(ctx, path: path, weight: weight * 0.78)
            strokeKeyCorners(ctx, width: width, height: height, weight: weight, round: round)
        case .scallop:
            strokeRim(ctx, path: path, weight: weight * 0.78)
            strokeScallop(ctx, width: width, height: height, weight: weight, round: round)
        case .sea:
            strokePlaque(ctx, width: width, height: height, weight: weight, round: round)
        }
        ctx.restoreGState()
    }

    private static func strokeRim(_ ctx: CGContext, path: CGPath, weight: CGFloat) {
        ctx.setLineWidth(weight * 2)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(3)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func strokeParallel(_ ctx: CGContext, path: CGPath, width: Int, height: Int, inset: CGFloat, line: CGFloat) {
        let cx = CGFloat(width) / 2
        let cy = CGFloat(height) / 2
        let sx = max(0.4, (CGFloat(width) - inset * 2) / CGFloat(width))
        let sy = max(0.4, (CGFloat(height) - inset * 2) / CGFloat(height))
        var transform = CGAffineTransform(translationX: cx, y: cy)
        transform = transform.scaledBy(x: sx, y: sy)
        transform = transform.translatedBy(x: -cx, y: -cy)
        guard let copy = path.copy(using: &transform) else { return }
        ctx.setLineWidth(max(1, line))
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.addPath(copy)
        ctx.strokePath()
    }

    private static func faceRect(width: Int, height: Int, inset: CGFloat) -> CGRect {
        CGRect(
            x: inset,
            y: inset,
            width: max(4, CGFloat(width) - inset * 2),
            height: max(4, CGFloat(height) - inset * 2)
        )
    }

    private static func strokeBracket(_ ctx: CGContext, width: Int, height: Int, weight: CGFloat, round: Bool) {
        let depth = min(weight * 4.2, min(CGFloat(width), CGFloat(height)) * 0.16)
        let rect = round
            ? inscribedRect(width: width, height: height, inset: weight * 2.2)
            : faceRect(width: width, height: height, inset: weight * 0.55)
        let path = CGMutablePath()
        let x0 = rect.minX
        let y0 = rect.minY
        let x1 = rect.maxX
        let y1 = rect.maxY
        let d = min(depth, rect.width * 0.28, rect.height * 0.28)
        path.move(to: CGPoint(x: x0 + d, y: y0))
        path.addLine(to: CGPoint(x: x1 - d, y: y0))
        path.addQuadCurve(to: CGPoint(x: x1, y: y0 + d), control: CGPoint(x: x1 - d, y: y0 + d))
        path.addLine(to: CGPoint(x: x1, y: y1 - d))
        path.addQuadCurve(to: CGPoint(x: x1 - d, y: y1), control: CGPoint(x: x1 - d, y: y1 - d))
        path.addLine(to: CGPoint(x: x0 + d, y: y1))
        path.addQuadCurve(to: CGPoint(x: x0, y: y1 - d), control: CGPoint(x: x0 + d, y: y1 - d))
        path.addLine(to: CGPoint(x: x0, y: y0 + d))
        path.addQuadCurve(to: CGPoint(x: x0 + d, y: y0), control: CGPoint(x: x0 + d, y: y0 + d))
        path.closeSubpath()
        ctx.setLineWidth(max(1, weight * 0.9))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// Extra room above and below the lettering, as a fraction of the face. The lion and the waves are not a uniform border.
    static func plaqueReserve(_ project: StampProject) -> (top: CGFloat, bottom: CGFloat) {
        switch project.borderStyle {
        case .sea: (0.04, 0.18)
        default: (0, 0)
        }
    }

    /// Meander frame with a wave-and-cloud base.
    private static func strokePlaque(_ ctx: CGContext, width: Int, height: Int, weight: CGFloat, round: Bool) {
        let sw = max(1.15, weight * 0.56)
        if round {
            strokeRoundPlaque(ctx, width: width, height: height, weight: weight, stroke: sw)
            return
        }
        let frame = faceRect(width: width, height: height, inset: sw * 0.45)
        let waveH = min(frame.width * 0.28, frame.height * 0.16, max(weight * 4.4, frame.height * 0.1))
        let band = sw * 6.3

        let path = CGMutablePath()
        let topLeft = CGPoint(x: frame.minX, y: frame.minY)
        let topRight = CGPoint(x: frame.maxX, y: frame.minY)
        let sideBottom = frame.maxY - waveH
        addKeyRun(path, from: topLeft, to: topRight, inward: CGPoint(x: 0, y: 1), stroke: sw)
        addKeyRun(path, from: topRight, to: CGPoint(x: frame.maxX, y: sideBottom), inward: CGPoint(x: -1, y: 0), stroke: sw)
        addKeyRun(path, from: CGPoint(x: frame.minX, y: sideBottom), to: topLeft, inward: CGPoint(x: 1, y: 0), stroke: sw)
        path.move(to: CGPoint(x: frame.minX, y: sideBottom))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX, y: sideBottom))

        ctx.setLineWidth(sw)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(2.5)
        ctx.addPath(path)
        ctx.strokePath()

        let innerTop = frame.minY + band + sw * 0.4
        let innerBottom = frame.maxY - waveH - sw
        if innerBottom - innerTop > band, frame.width > band * 3 {
            ctx.setLineWidth(max(1, sw * 0.85))
            ctx.stroke(CGRect(x: frame.minX + band, y: innerTop, width: frame.width - band * 2, height: innerBottom - innerTop))
        }

        strokeWaves(ctx, rect: frame, bandHeight: waveH, weight: sw)
    }

    /// On a round face the square key frame breaks apart, so the waves sit inside the rim.
    private static func strokeRoundPlaque(_ ctx: CGContext, width: Int, height: Int, weight: CGFloat, stroke sw: CGFloat) {
        strokeRim(ctx, path: ellipsePath(width: width, height: height), weight: weight * 0.72)
        let w = CGFloat(width)
        let h = CGFloat(height)
        let marginX = w * 0.18
        let yTop = h * 0.16
        let yBot = h * 0.68
        let g = sw * 2.6
        let path = CGMutablePath()
        path.move(to: CGPoint(x: marginX, y: yBot))
        path.addLine(to: CGPoint(x: marginX, y: yTop))
        path.addLine(to: CGPoint(x: w - marginX, y: yTop))
        path.addLine(to: CGPoint(x: w - marginX, y: yBot))
        path.move(to: CGPoint(x: marginX + g, y: yBot))
        path.addLine(to: CGPoint(x: marginX + g, y: yTop + g))
        path.addLine(to: CGPoint(x: w - marginX - g, y: yTop + g))
        path.addLine(to: CGPoint(x: w - marginX - g, y: yBot))
        ctx.setLineWidth(sw)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.addPath(path)
        ctx.strokePath()
        strokeWaves(ctx, rect: CGRect(x: marginX, y: yBot, width: w - marginX * 2, height: h * 0.22), bandHeight: h * 0.22, weight: sw)
    }

    private static func ellipsePath(width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 0.5, y: 0.5, width: CGFloat(width) - 1, height: CGFloat(height) - 1))
        return path
    }

    private static func strokeWaves(_ ctx: CGContext, rect: CGRect, bandHeight: CGFloat, weight: CGFloat) {
        let rows = 3
        let count = max(4, Int((rect.width / max(bandHeight * 1.15, 8)).rounded()))
        ctx.setLineWidth(max(1, weight * 0.85))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let path = CGMutablePath()
        for row in 0..<rows {
            let y = rect.maxY - bandHeight * (0.1 + CGFloat(row) * 0.2)
            let amplitude = bandHeight * (0.22 - CGFloat(row) * 0.03)
            let shift = row % 2 == 0 ? 0 : 0.5
            let span = rect.width / CGFloat(count)
            for index in 0..<count {
                let x0 = rect.minX + span * (CGFloat(index) + shift)
                let x1 = x0 + span
                guard x1 > rect.minX + 2, x0 < rect.maxX - 2 else { continue }
                let left = max(rect.minX, x0)
                let right = min(rect.maxX, x1)
                let mid = (x0 + x1) / 2
                path.move(to: CGPoint(x: left, y: y))
                path.addQuadCurve(to: CGPoint(x: right, y: y), control: CGPoint(x: mid, y: y - amplitude))
            }
        }
        ctx.addPath(path)
        ctx.strokePath()
        let puff = min(bandHeight * 0.34, rect.width * 0.07)
        let cloudY = rect.maxY - bandHeight * 0.78
        for offset in [-1.15, 0.0, 1.15] {
            strokeCloudPuff(ctx, at: CGPoint(x: rect.midX + puff * 2.3 * offset, y: cloudY), radius: puff, weight: weight)
        }
    }

    private static func strokeCloudPuff(_ ctx: CGContext, at point: CGPoint, radius: CGFloat, weight: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: point.x, y: point.y)
        ctx.setLineWidth(max(1, weight * 0.8))
        ctx.setLineCap(.round)
        let r = radius
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -r * 1.15, y: r * 0.35))
        ctx.addQuadCurve(to: CGPoint(x: -r * 0.15, y: -r * 0.55), control: CGPoint(x: -r * 1.05, y: -r * 0.45))
        ctx.addQuadCurve(to: CGPoint(x: r * 0.35, y: -r * 0.85), control: CGPoint(x: r * 0.05, y: -r * 1.15))
        ctx.addQuadCurve(to: CGPoint(x: r * 1.05, y: -r * 0.15), control: CGPoint(x: r * 0.95, y: -r * 0.85))
        ctx.addQuadCurve(to: CGPoint(x: r * 1.15, y: r * 0.35), control: CGPoint(x: r * 1.35, y: r * 0.15))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func strokeMeander(_ ctx: CGContext, project: StampProject, width: Int, height: Int, weight: CGFloat, round: Bool) {
        let sw = max(1.15, weight * 0.58)
        let polygon: [CGPoint]
        if round {
            let a = CGFloat(width) / 2 - weight * 1.9
            let b = CGFloat(height) / 2 - weight * 1.9
            polygon = regularPolygon(sides: 8, center: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2), radiusX: a, radiusY: b)
        } else {
            let rect = faceRect(width: width, height: height, inset: sw * 0.55)
            polygon = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ]
        }
        let path = CGMutablePath()
        let centroid = average(polygon)
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let inward = inwardNormal(from: a, to: b, toward: centroid)
            addKeyRun(path, from: a, to: b, inward: inward, stroke: sw)
        }
        ctx.setLineWidth(sw)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(2.5)
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// One Greek-key repeat. `g` is the gap between centerlines.
    private static func addKeyRun(_ path: CGMutablePath, from a: CGPoint, to b: CGPoint, inward: CGPoint, stroke sw: CGFloat) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }
        let ux = dx / length
        let uy = dy / length
        var g = sw * 2.05
        let margin = g * 2.2
        var period = g * 4
        var count = Int(((length - margin * 2) / period).rounded(.down))
        if count < 2 {
            let fit = max(sw * 1.25, (length * 0.72) / 8)
            g = fit
            period = g * 4
            count = Int(((length - g * 4) / period).rounded(.down))
        }
        guard count >= 1 else {
            path.move(to: a)
            path.addLine(to: b)
            return
        }
        let used = period * CGFloat(count)
        let lead = max(0, (length - used) / 2)
        func point(_ along: CGFloat, _ inn: CGFloat) -> CGPoint {
            CGPoint(x: a.x + ux * along + inward.x * inn, y: a.y + uy * along + inward.y * inn)
        }
        path.move(to: a)
        path.addLine(to: point(lead, 0))
        let fold: [(CGFloat, CGFloat)] = [
            (0, 3 * g),
            (2 * g, 3 * g),
            (2 * g, g),
            (g, g),
            (g, 2 * g),
            (3 * g, 2 * g),
            (3 * g, 0),
            (4 * g, 0),
        ]
        for index in 0..<count {
            let origin = lead + CGFloat(index) * period
            for step in fold {
                path.addLine(to: point(origin + step.0, step.1))
            }
        }
        path.addLine(to: b)
    }

    private static func strokeKeyCorners(_ ctx: CGContext, width: Int, height: Int, weight: CGFloat, round: Bool) {
        let rect = round
            ? inscribedRect(width: width, height: height, inset: weight * 0.9)
            : faceRect(width: width, height: height, inset: weight * 1.55)
        let sw = max(1.15, weight * 0.68)
        let arm = min(rect.width, rect.height) * (round ? 0.22 : 0.2)
        let gap = max(sw * 2.1, arm * 0.28)
        ctx.setLineWidth(sw)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(2)
        let path = CGMutablePath()
        // Straight double lines stop where the corner spiral begins, on the same tracks.
        func side(from: CGPoint, to: CGPoint, nx: CGFloat, ny: CGFloat) {
            path.move(to: from)
            path.addLine(to: to)
            path.move(to: CGPoint(x: from.x + nx * gap, y: from.y + ny * gap))
            path.addLine(to: CGPoint(x: to.x + nx * gap, y: to.y + ny * gap))
        }
        side(from: CGPoint(x: rect.minX + arm, y: rect.minY), to: CGPoint(x: rect.maxX - arm, y: rect.minY), nx: 0, ny: 1)
        side(from: CGPoint(x: rect.maxX, y: rect.minY + arm), to: CGPoint(x: rect.maxX, y: rect.maxY - arm), nx: -1, ny: 0)
        side(from: CGPoint(x: rect.maxX - arm, y: rect.maxY), to: CGPoint(x: rect.minX + arm, y: rect.maxY), nx: 0, ny: -1)
        side(from: CGPoint(x: rect.minX, y: rect.maxY - arm), to: CGPoint(x: rect.minX, y: rect.minY + arm), nx: 1, ny: 0)

        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        ]
        for (origin, ix, iy) in corners {
            func p(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + ix * a, y: origin.y + iy * b)
            }
            path.move(to: p(arm, 0))
            path.addLine(to: p(gap * 0.35, 0))
            path.addLine(to: p(gap * 0.35, gap * 0.35))
            path.addLine(to: p(0, gap * 0.35))
            path.addLine(to: p(0, arm))
            path.move(to: p(arm, gap))
            path.addLine(to: p(gap, gap))
            path.addLine(to: p(gap, arm))
            path.move(to: p(arm * 0.58, gap * 2))
            path.addLine(to: p(gap * 2, gap * 2))
            path.addLine(to: p(gap * 2, arm * 0.58))
        }
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func strokeScallop(_ ctx: CGContext, width: Int, height: Int, weight: CGFloat, round: Bool) {
        let amp = weight * 2.15
        let path = CGMutablePath()
        if round {
            let cx = CGFloat(width) / 2
            let cy = CGFloat(height) / 2
            let a = CGFloat(width) / 2 - weight * 2.4
            let b = CGFloat(height) / 2 - weight * 2.4
            let lobes = max(10, Int((.pi * 2 * min(a, b) / (amp * 3.2)).rounded()))
            let steps = lobes * 10
            for index in 0...steps {
                let t = CGFloat(index) / CGFloat(steps) * 2 * .pi
                let wave = (1 - cos(t * CGFloat(lobes))) * 0.5
                let x = cx + cos(t) * (a - amp * wave)
                let y = cy + sin(t) * (b - amp * wave)
                let point = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        } else {
            let rect = faceRect(width: width, height: height, inset: weight * 2.3)
            addArchedRect(path, rect: rect, amplitude: amp)
        }
        ctx.setLineWidth(max(1, weight * 0.72))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func addArchedRect(_ path: CGMutablePath, rect: CGRect, amplitude: CGFloat) {
        let sides: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: 0, y: 1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: -1, y: 0)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: 0, y: -1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: 1, y: 0)),
        ]
        var started = false
        for (from, to, inward) in sides {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = hypot(dx, dy)
            let count = max(3, Int((length / (amplitude * 2.5)).rounded()))
            let margin = min(amplitude * 0.85, length * 0.12)
            let span = (length - margin * 2) / CGFloat(count)
            func at(_ distance: CGFloat, _ bulge: CGFloat) -> CGPoint {
                let t = distance / length
                return CGPoint(
                    x: from.x + dx * t + inward.x * bulge,
                    y: from.y + dy * t + inward.y * bulge
                )
            }
            let start = at(0, 0)
            if !started {
                path.move(to: start)
                started = true
            } else {
                path.addLine(to: start)
            }
            path.addLine(to: at(margin, 0))
            for index in 0..<count {
                let end = margin + span * CGFloat(index + 1)
                let mid = end - span / 2
                path.addQuadCurve(to: at(end, 0), control: at(mid, amplitude))
            }
            path.addLine(to: at(length, 0))
        }
        path.closeSubpath()
    }

    private static func inscribedRect(width: Int, height: Int, inset: CGFloat) -> CGRect {
        let a = CGFloat(width) / 2 - inset
        let b = CGFloat(height) / 2 - inset
        let rw = max(4, a * 2 / CGFloat(2.0.squareRoot()))
        let rh = max(4, b * 2 / CGFloat(2.0.squareRoot()))
        return CGRect(x: CGFloat(width) / 2 - rw / 2, y: CGFloat(height) / 2 - rh / 2, width: rw, height: rh)
    }

    private static func regularPolygon(sides: Int, center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> [CGPoint] {
        (0..<sides).map { index in
            let angle = -CGFloat.pi / 2 + .pi / CGFloat(sides) + CGFloat(index) * 2 * .pi / CGFloat(sides)
            return CGPoint(x: center.x + cos(angle) * radiusX, y: center.y + sin(angle) * radiusY)
        }
    }

    private static func average(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let x = points.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(points.count)
        let y = points.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    private static func inwardNormal(from a: CGPoint, to b: CGPoint, toward center: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(0.001, hypot(dx, dy))
        var nx = -dy / length
        var ny = dx / length
        let midX = (a.x + b.x) / 2
        let midY = (a.y + b.y) / 2
        if (center.x - midX) * nx + (center.y - midY) * ny < 0 {
            nx = -nx
            ny = -ny
        }
        return CGPoint(x: nx, y: ny)
    }
}
