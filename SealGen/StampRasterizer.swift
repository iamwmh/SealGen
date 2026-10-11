import AppKit
import CoreText
import ImageIO

struct StampRaster {
    var mask: [UInt8]
    var design: [UInt8]
    var width: Int
    var height: Int
}

enum StampRasterizer {
    static func pixelSize(project: StampProject, longSide: Int) -> (width: Int, height: Int, pitch: Double) {
        let side = max(32, longSide)
        let longMM = max(project.widthMM, project.heightMM)
        let pitch = longMM / Double(side)
        let width = max(2, Int((project.widthMM / pitch).rounded()))
        let height = max(2, Int((project.heightMM / pitch).rounded()))
        return (width, height, pitch)
    }

    static func rasterize(project: StampProject, longSide: Int, mirror: Bool) -> StampRaster {
        let size = pixelSize(project: project, longSide: longSide)
        return rasterize(project: project, width: size.width, height: size.height, mirror: mirror)
    }

    static func rasterize(project: StampProject, width: Int, height: Int, mirror: Bool) -> StampRaster {
        let maskCtx = grayContext(width: width, height: height)
        let designCtx = grayContext(width: width, height: height)
        prepare(maskCtx, width: width, height: height, mirror: mirror)
        prepare(designCtx, width: width, height: height, mirror: mirror)

        let path = shapePath(project: project, width: width, height: height)
        maskCtx.setFillColor(gray: 1, alpha: 1)
        maskCtx.addPath(path)
        maskCtx.fillPath()

        designCtx.setFillColor(gray: 1, alpha: 1)
        designCtx.setStrokeColor(gray: 1, alpha: 1)
        designCtx.setLineCap(.round)
        designCtx.setLineJoin(.round)

        var imageInk = [UInt8](repeating: 0, count: width * height)
        for element in project.elements where element.kind == .image {
            stampImage(element, project: project, width: width, height: height, mirror: mirror, into: &imageInk)
        }

        for element in project.elements where element.kind == .pattern {
            drawPattern(element, project: project, ctx: designCtx, width: width, height: height)
        }
        for element in project.elements where element.kind == .text {
            drawText(element, project: project, ctx: designCtx, width: width, height: height)
        }
        BorderOrnament.draw(project: project, path: path, ctx: designCtx, width: width, height: height)

        let mask = readGray(maskCtx, width: width, height: height)
        var design = readGray(designCtx, width: width, height: height)
        for i in 0..<design.count where imageInk[i] > 0 {
            design[i] = 255
        }
        return StampRaster(mask: mask, design: design, width: width, height: height)
    }

    static func colorize(_ raster: StampRaster, yang: Bool) -> NSImage {
        let w = raster.width
        let h = raster.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let ink = (UInt8(176), UInt8(36), UInt8(30))
        let paper = (UInt8(250), UInt8(244), UInt8(232))
        let edge = (UInt8(96), UInt8(52), UInt8(40))

        for j in 0..<h {
            for i in 0..<w {
                let index = j * w + i
                let out = index * 4
                guard raster.mask[index] > 127 else {
                    pixels[out] = 0
                    pixels[out + 1] = 0
                    pixels[out + 2] = 0
                    pixels[out + 3] = 0
                    continue
                }
                let carved = raster.design[index] > 127
                let raisedInk = yang ? carved : !carved
                var rgb = raisedInk ? ink : paper
                if isEdge(mask: raster.mask, width: w, height: h, x: i, y: j) {
                    rgb = mix(rgb, edge, 0.62)
                }
                pixels[out] = rgb.0
                pixels[out + 1] = rgb.1
                pixels[out + 2] = rgb.2
                pixels[out + 3] = 255
            }
        }
        let image = ctx.makeImage()!
        return NSImage(cgImage: image, size: NSSize(width: w, height: h))
    }

    static func contentSizeMM(_ element: StampElement, project: StampProject) -> CGSize {
        let shorter = CGFloat(min(project.widthMM, project.heightMM))
        let em = CGFloat(element.fontSize) * shorter
        switch element.kind {
        case .image:
            let width = CGFloat(element.scale) * shorter
            let height = width / CGFloat(max(0.05, element.imageAspect))
            return CGSize(width: width + 0.8, height: height + 0.8)
        case .pattern:
            let side = CGFloat(element.scale) * shorter
            return CGSize(width: side, height: side)
        case .text:
            switch element.layout {
            case .horizontal:
                let lines = element.text.components(separatedBy: "\n")
                let widest = lines.map { measure($0, element: element, em: em).width }.max() ?? em
                let lineH = em * (1.05 + CGFloat(max(0, element.tracking)) * 0.25)
                return CGSize(width: max(em, widest) + em * 0.15, height: lineH * CGFloat(max(1, lines.count)))
            case .vertical:
                let count = max(1, Array(element.text.filter { !$0.isNewline }).count)
                let step = em * (1 + CGFloat(max(0, element.tracking)))
                return CGSize(width: em * 1.05, height: step * CGFloat(count))
            case .gridLeft, .gridRight:
                let count = max(1, Array(element.text.filter { !$0.isNewline }).count)
                let (cols, rows) = gridShape(count: count)
                let cell = em * (1 + CGFloat(max(0, element.tracking)))
                return CGSize(width: cell * CGFloat(cols), height: cell * CGFloat(rows))
            case .ring:
                let radius = CGFloat(element.scale) * shorter * 0.5
                let outer = (radius + em * 0.55) * 2
                return CGSize(width: outer, height: outer)
            case .fill:
                let frame = innerTextRect(project: project, coverage: CGFloat(element.scale))
                return CGSize(width: frame.width * CGFloat(project.widthMM), height: frame.height * CGFloat(project.heightMM))
            }
        }
    }

    private static func grayContext(width: Int, height: Int) -> CGContext {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        return ctx
    }

    private static func prepare(_ ctx: CGContext, width: Int, height: Int, mirror: Bool) {
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        if mirror {
            ctx.translateBy(x: CGFloat(width), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
    }

    private static func readGray(_ ctx: CGContext, width: Int, height: Int) -> [UInt8] {
        let rowBytes = ctx.bytesPerRow
        let src = ctx.data!.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                out[y * width + x] = src[y * rowBytes + x] > 127 ? 255 : 0
            }
        }
        return out
    }

    private static func shapePath(project: StampProject, width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()
        let rect = CGRect(x: 0.5, y: 0.5, width: CGFloat(width) - 1, height: CGFloat(height) - 1)
        switch project.shape {
        case .circle, .ellipse:
            path.addEllipse(in: rect)
        case .square:
            let rx = CGFloat(project.cornerRadiusMM / project.widthMM) * CGFloat(width)
            let ry = CGFloat(project.cornerRadiusMM / project.heightMM) * CGFloat(height)
            path.addPath(CGPath(roundedRect: rect, cornerWidth: min(rx, rect.width / 2), cornerHeight: min(ry, rect.height / 2), transform: nil))
        case .heart:
            addPolygon(path, StampPaths.heart(), width: width, height: height)
        case .free:
            addPolygon(path, project.freePoints, width: width, height: height)
        }
        return path
    }

    private static func addPolygon(_ path: CGMutablePath, _ points: [CGPoint], width: Int, height: Int) {
        guard points.count >= 3 else { return }
        path.move(to: CGPoint(x: points[0].x * CGFloat(width), y: points[0].y * CGFloat(height)))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * CGFloat(width), y: point.y * CGFloat(height)))
        }
        path.closeSubpath()
    }

    private struct Glyph {
        var text: String
        var x: CGFloat
        var y: CGFloat
        var spin: CGFloat
        var em: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }

    private static func drawText(_ element: StampElement, project: StampProject, ctx: CGContext, width: Int, height: Int) {
        let glyphs = layoutGlyphs(element, project: project, width: width, height: height)
        guard !glyphs.isEmpty else { return }
        let cx = CGFloat(element.x) * CGFloat(width)
        let cy = CGFloat(element.y) * CGFloat(height)
        let rotation = CGFloat(element.rotation * .pi / 180)
        let em = CGFloat(element.fontSize) * min(CGFloat(width), CGFloat(height))
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: rotation)
        for glyph in glyphs {
            let size = glyph.em > 0 ? glyph.em : em
            let font = ctFont(element, size: size)
            let kern = glyph.em > 0 ? 0 : CGFloat(element.tracking) * size
            drawGlyph(glyph.text, font: font, kern: kern, ctx: ctx, x: glyph.x, y: glyph.y, spin: glyph.spin, scaleX: glyph.scaleX, scaleY: glyph.scaleY)
        }
        ctx.restoreGState()
    }

    private static func layoutGlyphs(_ element: StampElement, project: StampProject, width: Int, height: Int) -> [Glyph] {
        let shorter = min(CGFloat(width), CGFloat(height))
        let em = CGFloat(element.fontSize) * shorter
        switch element.layout {
        case .horizontal:
            let lines = element.text.components(separatedBy: "\n")
            let font = ctFont(element, size: em)
            let kern = CGFloat(element.tracking) * em
            let heights = lines.map { lineHeight($0, font: font, kern: kern) }
            let lineH = max(em, heights.max() ?? em) * (1.02 + CGFloat(max(0, element.tracking)) * 0.2)
            let total = lineH * CGFloat(max(1, lines.count))
            return lines.enumerated().map { index, line in
                Glyph(text: line, x: 0, y: -total / 2 + lineH * (CGFloat(index) + 0.5), spin: 0)
            }
        case .vertical:
            let chars = Array(element.text.filter { !$0.isNewline })
            let step = em * (1 + CGFloat(max(0, element.tracking)))
            let total = step * CGFloat(chars.count)
            return chars.enumerated().map { index, char in
                Glyph(text: String(char), x: 0, y: -total / 2 + step * (CGFloat(index) + 0.5), spin: 0)
            }
        case .gridLeft, .gridRight:
            let chars = Array(element.text.filter { !$0.isNewline })
            guard !chars.isEmpty else { return [] }
            let (cols, rows) = gridShape(count: chars.count)
            let cell = em * (1 + CGFloat(max(0, element.tracking)))
            let totalW = cell * CGFloat(cols)
            let totalH = cell * CGFloat(rows)
            return chars.enumerated().map { index, char in
                let col: Int
                let row: Int
                if element.layout == .gridRight {
                    let columnFromRight = index / rows
                    row = index % rows
                    col = cols - 1 - columnFromRight
                } else {
                    col = index % cols
                    row = index / cols
                }
                let x = -totalW / 2 + cell * (CGFloat(col) + 0.5)
                let y = -totalH / 2 + cell * (CGFloat(row) + 0.5)
                return Glyph(text: String(char), x: x, y: y, spin: 0)
            }
        case .ring:
            let chars = Array(element.text.filter { !$0.isNewline })
            guard !chars.isEmpty else { return [] }
            let radius = CGFloat(element.scale) * shorter * 0.5
            return chars.enumerated().map { index, char in
                let angle = -CGFloat.pi / 2 + (chars.count == 1 ? 0 : CGFloat(index) / CGFloat(chars.count) * 2 * .pi)
                return Glyph(text: String(char), x: cos(angle) * radius, y: sin(angle) * radius, spin: angle + .pi / 2)
            }
        case .fill:
            return layoutFill(element, project: project, width: width, height: height)
        }
    }

    /// Box the enhanced layout fills, in 0...1 face coordinates (y down).
    static func innerTextRect(project: StampProject, coverage: CGFloat) -> CGRect {
        let cover = min(1, max(0.45, coverage))
        let reachX = CGFloat(BorderOrnament.reachMM(project) / project.widthMM) + 0.02
        let reachY = CGFloat(BorderOrnament.reachMM(project) / project.heightMM) + 0.02
        let rect: CGRect
        switch project.shape {
        case .circle, .ellipse:
            let a = max(0.08, 0.5 - reachX)
            let b = max(0.08, 0.5 - reachY)
            let rw = a * 2 * 0.86
            let rh = b * 2 * 0.86
            rect = CGRect(x: 0.5 - rw / 2, y: 0.5 - rh / 2, width: rw, height: rh)
        case .heart:
            rect = CGRect(x: reachX + 0.1, y: reachY + 0.12, width: max(0.2, 1 - 2 * reachX - 0.2), height: max(0.2, 1 - 2 * reachY - 0.22))
        case .free:
            rect = CGRect(x: reachX + 0.06, y: reachY + 0.06, width: max(0.2, 1 - 2 * reachX - 0.12), height: max(0.2, 1 - 2 * reachY - 0.12))
        case .square:
            let extra = CGFloat(project.cornerRadiusMM / project.widthMM) * 0.2
            let x = reachX + extra
            let y = reachY + extra
            rect = CGRect(x: x, y: y, width: max(0.2, 1 - 2 * x), height: max(0.2, 1 - 2 * y))
        }
        let rw = rect.width * cover
        let rh = rect.height * cover
        var box = CGRect(x: 0.5 - rw / 2, y: 0.5 - rh / 2, width: rw, height: rh)
        let reserve = BorderOrnament.plaqueReserve(project)
        if reserve.top > 0 || reserve.bottom > 0 {
            let y0 = max(box.minY, reserve.top)
            let y1 = min(box.maxY, 1 - reserve.bottom)
            if y1 - y0 > 0.16 {
                box = CGRect(x: box.minX, y: y0, width: box.width, height: y1 - y0)
            }
        }
        return box
    }

    private static func layoutFill(_ element: StampElement, project: StampProject, width: Int, height: Int) -> [Glyph] {
        let frame = innerTextRect(project: project, coverage: CGFloat(element.scale))
        let left = frame.minX * CGFloat(width)
        let top = frame.minY * CGFloat(height)
        let boxW = frame.width * CGFloat(width)
        let boxH = frame.height * CGFloat(height)
        guard boxW > 4, boxH > 4 else { return [] }
        let originX = CGFloat(element.x) * CGFloat(width)
        let originY = CGFloat(element.y) * CGFloat(height)
        let gap = CGFloat(min(0.4, max(0, element.tracking)))
        let maxStretch: CGFloat = 1.7

        func glyph(_ char: Character, cellX: CGFloat, cellY: CGFloat, cellW: CGFloat, cellH: CGFloat) -> Glyph {
            var drawW = cellW * (1 - gap)
            var drawH = cellH * (1 - gap)
            if drawW > drawH * maxStretch { drawW = drawH * maxStretch }
            if drawH > drawW * maxStretch { drawH = drawW * maxStretch }
            let base: CGFloat = 100
            return Glyph(
                text: String(char),
                x: cellX - originX,
                y: cellY - originY,
                spin: 0,
                em: base,
                scaleX: drawW / base,
                scaleY: drawH / base
            )
        }

        if element.text.contains("\n") {
            let rows = element.text.components(separatedBy: "\n").map { line in
                Array(line.filter { !$0.isWhitespace })
            }.filter { !$0.isEmpty }
            guard !rows.isEmpty else { return [] }
            let rowH = boxH / CGFloat(rows.count)
            var glyphs: [Glyph] = []
            for (rowIndex, row) in rows.enumerated() {
                let cellW = boxW / CGFloat(row.count)
                let cy = top + rowH * (CGFloat(rowIndex) + 0.5)
                for (col, char) in row.enumerated() {
                    let cx = left + cellW * (CGFloat(col) + 0.5)
                    glyphs.append(glyph(char, cellX: cx, cellY: cy, cellW: cellW, cellH: rowH))
                }
            }
            return glyphs
        }

        let chars = Array(element.text.filter { !$0.isNewline && !$0.isWhitespace })
        guard !chars.isEmpty else { return [] }
        let (cols, rows) = fillGrid(count: chars.count, aspect: boxW / boxH)
        let cellW = boxW / CGFloat(cols)
        let cellH = boxH / CGFloat(rows)
        return chars.enumerated().map { index, char in
            let columnFromRight = index / rows
            let row = index % rows
            let col = cols - 1 - columnFromRight
            let cx = left + cellW * (CGFloat(col) + 0.5)
            let cy = top + cellH * (CGFloat(row) + 0.5)
            return glyph(char, cellX: cx, cellY: cy, cellW: cellW, cellH: cellH)
        }
    }

    private static func fillGrid(count: Int, aspect: CGFloat) -> (Int, Int) {
        var best = (cols: 1, rows: count)
        var bestScore = -CGFloat.infinity
        let maxStretch: CGFloat = 1.7
        for cols in 1...count {
            let rows = Int((Double(count) + Double(cols) - 1) / Double(cols))
            let cellW = aspect / CGFloat(cols)
            let cellH = 1 / CGFloat(rows)
            let drawW = min(cellW, cellH * maxStretch)
            let drawH = min(cellH, cellW * maxStretch)
            let empty = CGFloat(cols * rows - count)
            let score = drawW * drawH * CGFloat(count) - empty * drawW * drawH * 0.12
            if score > bestScore {
                bestScore = score
                best = (cols, rows)
            }
        }
        return best
    }

    private static func drawGlyph(_ text: String, font: CTFont, kern: CGFloat, ctx: CGContext, x: CGFloat, y: CGFloat, spin: CGFloat, scaleX: CGFloat = 1, scaleY: CGFloat = 1) {
        guard !text.isEmpty else { return }
        let line = CTLineCreateWithAttributedString(attributed(text, font: font, kern: kern))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: spin)
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = CGPoint(x: -width / 2, y: -(ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func drawPattern(_ element: StampElement, project: StampProject, ctx: CGContext, width: Int, height: Int) {
        let shorter = min(CGFloat(width), CGFloat(height))
        let box = CGFloat(element.scale) * shorter
        guard box > 2 else { return }
        let cx = CGFloat(element.x) * CGFloat(width)
        let cy = CGFloat(element.y) * CGFloat(height)
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: CGFloat(element.rotation * .pi / 180))
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        let line = max(1.4, box * 0.045)
        ctx.setLineWidth(line)
        switch element.pattern {
        case .plum: drawPlum(ctx, box: box, line: line)
        case .cloud: drawCloud(ctx, box: box)
        case .taiji: drawTaiji(ctx, box: box)
        case .sun: drawSun(ctx, box: box, line: line)
        case .diamond: drawDiamond(ctx, box: box)
        case .meander: drawMeander(ctx, box: box, line: line)
        }
        ctx.restoreGState()
    }

    private static func drawPlum(_ ctx: CGContext, box: CGFloat, line: CGFloat) {
        let petal = box * 0.16
        ctx.setLineWidth(line)
        for i in 0..<5 {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 5
            let center = CGPoint(x: cos(angle) * petal * 1.25, y: sin(angle) * petal * 1.25)
            ctx.addEllipse(in: CGRect(x: center.x - petal, y: center.y - petal, width: petal * 2, height: petal * 2))
        }
        ctx.addEllipse(in: CGRect(x: -petal * 0.38, y: -petal * 0.38, width: petal * 0.76, height: petal * 0.76))
        ctx.strokePath()
    }

    private static func drawCloud(_ ctx: CGContext, box: CGFloat) {
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.22, 0.06, 0.22),
            (0.02, -0.02, 0.28),
            (0.24, 0.08, 0.2),
            (-0.02, 0.16, 0.16),
            (0.12, -0.18, 0.14),
        ]
        for blob in blobs {
            let radius = box * blob.2
            ctx.addEllipse(in: CGRect(x: box * blob.0 - radius, y: box * blob.1 - radius, width: radius * 2, height: radius * 2))
        }
        ctx.fillPath()
    }

    private static func drawTaiji(_ ctx: CGContext, box: CGFloat) {
        let radius = box * 0.46
        ctx.setLineWidth(max(1.5, box * 0.04))
        ctx.strokeEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        ctx.move(to: CGPoint(x: 0, y: -radius))
        ctx.addArc(center: CGPoint(x: 0, y: -radius / 2), radius: radius / 2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        ctx.addArc(center: CGPoint(x: 0, y: radius / 2), radius: radius / 2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
        ctx.strokePath()
        let eye = radius * 0.11
        ctx.fillEllipse(in: CGRect(x: -eye, y: -radius / 2 - eye, width: eye * 2, height: eye * 2))
        ctx.fillEllipse(in: CGRect(x: -eye, y: radius / 2 - eye, width: eye * 2, height: eye * 2))
    }

    private static func drawSun(_ ctx: CGContext, box: CGFloat, line: CGFloat) {
        ctx.setLineWidth(line)
        let inner = box * 0.16
        ctx.strokeEllipse(in: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2))
        for i in 0..<12 {
            let angle = CGFloat(i) / 12 * 2 * .pi
            ctx.move(to: CGPoint(x: cos(angle) * box * 0.24, y: sin(angle) * box * 0.24))
            ctx.addLine(to: CGPoint(x: cos(angle) * box * 0.46, y: sin(angle) * box * 0.46))
        }
        ctx.strokePath()
    }

    private static func drawDiamond(_ ctx: CGContext, box: CGFloat) {
        for scale in [CGFloat(0.46), 0.30, 0.15] {
            let d = box * scale
            ctx.move(to: CGPoint(x: 0, y: -d))
            ctx.addLine(to: CGPoint(x: d, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: d))
            ctx.addLine(to: CGPoint(x: -d, y: 0))
            ctx.closePath()
        }
        ctx.strokePath()
    }

    private static func drawMeander(_ ctx: CGContext, box: CGFloat, line: CGFloat) {
        ctx.setLineWidth(line)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        let outer = box * 0.46
        func frame(_ inset: CGFloat) {
            let s = outer - inset
            guard s > line else { return }
            ctx.stroke(CGRect(x: -s, y: -s, width: s * 2, height: s * 2))
        }
        frame(0)
        frame(line * 2.4)
        let arm = line * 2.4
        let s = outer - line * 2.4
        // Breaks that turn the double frame into a simple key at each side.
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: -arm / 2, y: -outer - line, width: arm, height: line * 3))
        ctx.fill(CGRect(x: -arm / 2, y: s - line, width: arm, height: line * 3))
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.move(to: CGPoint(x: -arm / 2, y: -outer))
        ctx.addLine(to: CGPoint(x: -arm / 2, y: -s))
        ctx.move(to: CGPoint(x: arm / 2, y: -outer))
        ctx.addLine(to: CGPoint(x: arm / 2, y: -s))
        ctx.strokePath()
    }

    private static func stampImage(_ element: StampElement, project: StampProject, width: Int, height: Int, mirror: Bool, into ink: inout [UInt8]) {
        guard let data = element.imageData, let image = decodeImage(data) else { return }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        prepare(ctx, width: width, height: height, mirror: mirror)
        let shorter = min(CGFloat(width), CGFloat(height))
        let destW = CGFloat(element.scale) * shorter
        let destH = destW / CGFloat(max(0.05, element.imageAspect))
        let cx = CGFloat(element.x) * CGFloat(width)
        let cy = CGFloat(element.y) * CGFloat(height)
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: CGFloat(element.rotation * .pi / 180))
        ctx.translateBy(x: 0, y: 0)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: -destW / 2, y: -destH / 2, width: destW, height: destH))
        ctx.restoreGState()

        let bytes = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let threshold = Float(element.threshold)
        for i in 0..<(width * height) {
            let o = i * 4
            let alpha = Float(bytes[o + 3])
            if alpha < 8 { continue }
            let r = Float(bytes[o]) / alpha
            let g = Float(bytes[o + 1]) / alpha
            let b = Float(bytes[o + 2]) / alpha
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let on: Bool
            switch element.inkMode {
            case .dark: on = luma < threshold
            case .light: on = luma > threshold
            case .opaque: on = alpha > threshold * 255
            }
            if on { ink[i] = 255 }
        }
    }

    private static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        guard orientation != 1 else { return image }
        return oriented(image, orientation: orientation)
    }

    private static func oriented(_ image: CGImage, orientation: UInt32) -> CGImage {
        let w = image.width
        let h = image.height
        var size = CGSize(width: w, height: h)
        var transform = CGAffineTransform.identity
        switch orientation {
        case 2:
            transform = transform.translatedBy(x: size.width, y: 0).scaledBy(x: -1, y: 1)
        case 3:
            transform = transform.translatedBy(x: size.width, y: size.height).rotated(by: .pi)
        case 4:
            transform = transform.translatedBy(x: 0, y: size.height).scaledBy(x: 1, y: -1)
        case 5:
            size = CGSize(width: h, height: w)
            transform = transform.translatedBy(x: 0, y: size.width).rotated(by: .pi / 2).scaledBy(x: -1, y: 1)
        case 6:
            size = CGSize(width: h, height: w)
            transform = transform.translatedBy(x: size.width, y: 0).rotated(by: .pi / 2)
        case 7:
            size = CGSize(width: h, height: w)
            transform = transform.translatedBy(x: size.height, y: size.width).rotated(by: -.pi / 2).scaledBy(x: -1, y: 1)
        case 8:
            size = CGSize(width: h, height: w)
            transform = transform.translatedBy(x: 0, y: size.height).rotated(by: -.pi / 2)
        default:
            return image
        }
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.concatenate(transform)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    private static func ctFont(_ element: StampElement, size: CGFloat) -> CTFont {
        let face = SealFont.named(element.fontID)
        let name = element.bold ? face.heavy : face.regular
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    private static func attributed(_ text: String, font: CTFont, kern: CGFloat) -> NSAttributedString {
        let color = CGColor(gray: 1, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: kern,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func lineHeight(_ text: String, font: CTFont, kern: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(text, font: font, kern: kern))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return max(ascent + descent, 1)
    }

    private static func measure(_ text: String, element: StampElement, em: CGFloat) -> CGSize {
        let font = ctFont(element, size: em)
        let kern = CGFloat(element.tracking) * em
        let line = CTLineCreateWithAttributedString(attributed(text, font: font, kern: kern))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return CGSize(width: width, height: ascent + descent)
    }

    private static func gridShape(count: Int) -> (Int, Int) {
        if count == 4 { return (2, 2) }
        let cols = max(1, Int(ceil(sqrt(Double(count)))))
        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        return (cols, rows)
    }

    private static func isEdge(mask: [UInt8], width: Int, height: Int, x: Int, y: Int) -> Bool {
        if x == 0 || y == 0 || x == width - 1 || y == height - 1 { return true }
        let row = width
        return mask[y * row + x - 1] < 128 || mask[y * row + x + 1] < 128
            || mask[(y - 1) * row + x] < 128 || mask[(y + 1) * row + x] < 128
    }

    private static func mix(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8), _ t: Double) -> (UInt8, UInt8, UInt8) {
        func channel(_ u: UInt8, _ v: UInt8) -> UInt8 {
            UInt8(Double(u) * (1 - t) + Double(v) * t)
        }
        return (channel(a.0, b.0), channel(a.1, b.1), channel(a.2, b.2))
    }
}
