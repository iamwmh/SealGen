import Foundation
import CoreGraphics

enum StampShape: String, CaseIterable, Identifiable {
    case circle, square, ellipse, heart, free
    var id: String { rawValue }
    var label: String {
        switch self {
        case .circle: UIText.text("圆形", "Circle")
        case .square: UIText.text("方形", "Square")
        case .ellipse: UIText.text("椭圆", "Oval")
        case .heart: UIText.text("心形", "Heart")
        case .free: UIText.text("手绘", "Drawn")
        }
    }
}

enum CarveMode: String, CaseIterable, Identifiable {
    case yang, yin
    var id: String { rawValue }
    var title: String { self == .yang ? UIText.text("阳刻", "Relief") : UIText.text("阴刻", "Intaglio") }
    var subtitle: String { self == .yang ? UIText.text("朱文 · 红字", "Prints red") : UIText.text("白文 · 白字", "Prints white") }
    var detail: String {
        self == .yang
            ? UIText.text("笔画凸起，盖出来是红字。", "Strokes are raised and print red.")
            : UIText.text("笔画凹陷，盖出来是白字。", "Strokes are recessed and print white.")
    }
}

enum TextLayout: String, CaseIterable, Identifiable {
    case horizontal, vertical, gridLeft, gridRight, ring, fill
    var id: String { rawValue }
    var label: String {
        switch self {
        case .horizontal: UIText.text("横排", "Horizontal")
        case .vertical: UIText.text("竖排", "Vertical")
        case .gridLeft: UIText.text("田字·左起", "Grid, left")
        case .gridRight: UIText.text("田字·右起", "Grid, right")
        case .ring: UIText.text("环排", "Ring")
        case .fill: UIText.text("增强排版", "Fill face")
        }
    }

    /// Ring radius and the fill coverage live in `scale`. Other layouts use `fontSize`.
    var adjustsScale: Bool {
        self == .ring || self == .fill
    }
}

enum BorderStyle: String, CaseIterable, Identifiable {
    case line, double, bracket, meander, keyCorner, scallop, sea
    var id: String { rawValue }
    var label: String {
        switch self {
        case .line: UIText.text("单线", "Line")
        case .double: UIText.text("双线", "Double")
        case .bracket: UIText.text("委角", "Notched")
        case .meander: UIText.text("回纹", "Meander")
        case .keyCorner: UIText.text("拐子", "Fret")
        case .scallop: UIText.text("花瓣", "Petal")
        case .sea: UIText.text("海水", "Waves")
        }
    }
}

enum ElementKind: String, Codable {
    case text, image, pattern
}

enum PatternKind: String, CaseIterable, Identifiable {
    case plum, cloud, taiji, sun, diamond, meander
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plum: UIText.text("梅花", "Plum")
        case .cloud: UIText.text("祥云", "Cloud")
        case .taiji: UIText.text("太极", "Taiji")
        case .sun: UIText.text("芒纹", "Rays")
        case .diamond: UIText.text("菱纹", "Diamond")
        case .meander: UIText.text("回纹", "Meander")
        }
    }
}

enum InkMode: String, CaseIterable, Identifiable {
    case dark, light, opaque
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: UIText.text("深色为图案", "Dark ink")
        case .light: UIText.text("浅色为图案", "Light ink")
        case .opaque: UIText.text("不透明为图案", "Opaque ink")
        }
    }
}

enum StoneColor: String, CaseIterable, Identifiable {
    case cinnabar, tianhuang, qingtian, ebony
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cinnabar: UIText.text("朱砂", "Cinnabar")
        case .tianhuang: UIText.text("田黄", "Tianhuang")
        case .qingtian: UIText.text("青田", "Qingtian")
        case .ebony: UIText.text("黑檀", "Ebony")
        }
    }
}

struct SealFont: Identifiable, Hashable {
    var id: String
    var regular: String
    var heavy: String

    var label: String {
        switch id {
        case "kai": UIText.text("楷体", "Kai")
        case "song": UIText.text("宋体", "Song")
        case "hei": UIText.text("黑体", "Hei")
        case "ping": UIText.text("苹方", "PingFang")
        case "stkaiti": UIText.text("华文楷体", "ST Kai")
        case "stsong": UIText.text("华文宋体", "ST Song")
        case "hiragino": UIText.text("冬青黑体", "Hiragino")
        default: id
        }
    }

    static let all: [SealFont] = [
        SealFont(id: "kai", regular: "STKaitiSC-Regular", heavy: "STKaitiSC-Black"),
        SealFont(id: "song", regular: "STSongti-SC-Regular", heavy: "STSongti-SC-Black"),
        SealFont(id: "hei", regular: "STHeitiSC-Light", heavy: "STHeitiSC-Medium"),
        SealFont(id: "ping", regular: "PingFangSC-Regular", heavy: "PingFangSC-Semibold"),
        SealFont(id: "stkaiti", regular: "STKaiti", heavy: "STKaiti"),
        SealFont(id: "stsong", regular: "STSong", heavy: "STSong"),
        SealFont(id: "hiragino", regular: "HiraginoSansGB-W3", heavy: "HiraginoSansGB-W6"),
    ]

    static func named(_ id: String) -> SealFont {
        all.first { $0.id == id } ?? all[0]
    }
}

struct StampElement: Identifiable {
    var id = UUID()
    var kind: ElementKind
    var text: String = "福"
    var fontID: String = "kai"
    var bold: Bool = true
    var fontSize: Double = 0.46
    var tracking: Double = 0.02
    var layout: TextLayout = .horizontal
    var imageData: Data?
    var imageAspect: Double = 1
    var inkMode: InkMode = .dark
    var threshold: Double = 0.62
    var pattern: PatternKind = .plum
    var x: Double = 0.5
    var y: Double = 0.5
    var scale: Double = 0.72
    var rotation: Double = 0

    var title: String {
        switch kind {
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? UIText.text("文字", "Text") : trimmed
        case .image:
            return UIText.text("图片", "Image")
        case .pattern:
            return pattern.label
        }
    }

    var subtitle: String {
        switch kind {
        case .text:
            return "\(SealFont.named(fontID).label) · \(layout.label)"
        case .image:
            return inkMode.label
        case .pattern:
            return UIText.text("纹样", "Motif")
        }
    }

    static func makeText(_ text: String) -> StampElement {
        StampElement(kind: .text, text: text)
    }

    static func makePattern(_ kind: PatternKind) -> StampElement {
        StampElement(kind: .pattern, fontSize: 0.4, pattern: kind, scale: 0.42)
    }

    static func makeImage(data: Data, aspect: Double) -> StampElement {
        StampElement(kind: .image, imageData: data, imageAspect: aspect, scale: 0.62)
    }
}

struct StampProject {
    var shape: StampShape = .circle
    var widthMM: Double = 40
    var heightMM: Double = 40
    var cornerRadiusMM: Double = 0
    var freePoints: [CGPoint] = []
    var mode: CarveMode = .yang
    var borderMM: Double = 1.5
    var borderStyle: BorderStyle = .line
    var elements: [StampElement] = [StampElement.makeText("福")]

    static var sample: StampProject { StampProject() }

    mutating func normalize() {
        widthMM = min(120, max(8, widthMM))
        heightMM = min(120, max(8, heightMM))
        if shape == .circle { heightMM = widthMM }
        let shorter = min(widthMM, heightMM)
        cornerRadiusMM = min(shorter / 2, max(0, cornerRadiusMM))
        borderMM = min(shorter / 3, max(0, borderMM))
    }
}

enum PathSmooth {
    static func decimate(_ pts: [CGPoint], minDist: CGFloat) -> [CGPoint] {
        guard let first = pts.first else { return [] }
        var out = [first]
        for p in pts.dropFirst() {
            let last = out[out.count - 1]
            if hypot(p.x - last.x, p.y - last.y) >= minDist { out.append(p) }
        }
        return out
    }

    static func rdpClosed(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 3, let first = pts.first else { return pts }
        var open = pts
        if hypot(open[open.count - 1].x - first.x, open[open.count - 1].y - first.y) > 0.0001 {
            open.append(first)
        }
        var simplified = rdp(open, epsilon: epsilon)
        if simplified.count >= 2 {
            let a = simplified[0]
            let b = simplified[simplified.count - 1]
            if hypot(a.x - b.x, a.y - b.y) < 0.0001 { simplified.removeLast() }
        }
        return simplified
    }

    static func chaikinClosed(_ pts: [CGPoint], iterations: Int) -> [CGPoint] {
        guard pts.count >= 3 else { return pts }
        var current = pts
        for _ in 0..<iterations {
            var next: [CGPoint] = []
            next.reserveCapacity(current.count * 2)
            let n = current.count
            for i in 0..<n {
                let p = current[i]
                let q = current[(i + 1) % n]
                next.append(CGPoint(x: 0.75 * p.x + 0.25 * q.x, y: 0.75 * p.y + 0.25 * q.y))
                next.append(CGPoint(x: 0.25 * p.x + 0.75 * q.x, y: 0.25 * p.y + 0.75 * q.y))
            }
            current = next
        }
        return current
    }

    private static func rdp(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var maxD: CGFloat = 0
        var index = 0
        let a = pts[0]
        let b = pts[pts.count - 1]
        if pts.count > 2 {
            for i in 1..<(pts.count - 1) {
                let d = distance(pts[i], a, b)
                if d > maxD {
                    maxD = d
                    index = i
                }
            }
        }
        if maxD > epsilon, index > 0 {
            let left = rdp(Array(pts[0...index]), epsilon: epsilon)
            let right = rdp(Array(pts[index...]), epsilon: epsilon)
            return left.dropLast() + right
        }
        return [a, b]
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-10 { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

enum StampPaths {
    static func heart(samples: Int = 96) -> [CGPoint] {
        var raw: [CGPoint] = []
        raw.reserveCapacity(samples)
        for i in 0..<samples {
            let t = (CGFloat(i) / CGFloat(samples)) * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
            raw.append(CGPoint(x: x, y: y))
        }
        return fit(raw, pad: 0.07)
    }

    static func fit(_ raw: [CGPoint], pad: CGFloat) -> [CGPoint] {
        guard let minX = raw.map(\.x).min(), let maxX = raw.map(\.x).max(),
              let minY = raw.map(\.y).min(), let maxY = raw.map(\.y).max(),
              maxX > minX, maxY > minY else { return raw }
        let span = 1 - 2 * pad
        return raw.map { p in
            CGPoint(
                x: pad + (p.x - minX) / (maxX - minX) * span,
                y: pad + (p.y - minY) / (maxY - minY) * span
            )
        }
    }
}
