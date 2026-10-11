import SwiftUI
import UniformTypeIdentifiers

struct DesignCanvasView: View {
    var document: StampDocument
    @Environment(\.locale) private var locale
    @State private var livePoints: [CGPoint] = []

    private func t(_ chinese: String, _ english: String) -> String {
        locale.text(chinese, english)
    }
    @State private var drag: DragAction?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let rect = stampRect(in: geo.size)
                ZStack {
                    LinearGradient(colors: [Theme.paper, Theme.paperDeep], startPoint: .top, endPoint: .bottom)
                    if let image = document.impression, document.project.shape != .free || document.project.freePoints.count >= 3 {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                    }
                    overlay(rect: rect)
                    if document.isDrawingShape {
                        drawingHint(rect: rect)
                    }
                }
                .contentShape(Rectangle())
                .gesture(gesture(in: rect))
                .onTapGesture { focused = true }
            }
            footer
        }
        .background(Theme.paper)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onDeleteCommand { document.deleteSelected() }
        .onKeyPress(.leftArrow) { document.nudge(dxMM: -0.4, dyMM: 0); return .handled }
        .onKeyPress(.rightArrow) { document.nudge(dxMM: 0.4, dyMM: 0); return .handled }
        .onKeyPress(.upArrow) { document.nudge(dxMM: 0, dyMM: -0.4); return .handled }
        .onKeyPress(.downArrow) { document.nudge(dxMM: 0, dyMM: 0.4); return .handled }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in document.addImage(data: data) }
            }
            return true
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.showMirror ? t("镜像印面", "Mirrored face") : t("钤印效果", "Impression"))
                    .font(.custom("STSongti-SC-Regular", size: 22))
                    .foregroundStyle(Theme.ink)
                Text(document.showMirror ? t("这是刻在章面上的方向，左右已经反过来", "This is the direction cut into the seal. Left and right are reversed.") : t("这是盖在纸上的样子，文字是正的", "This is how it prints on paper. The characters read correctly."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink.opacity(0.62))
            }
            Spacer()
            Picker(t("预览", "Preview"), selection: Binding(
                get: { document.showMirror ? 1 : 0 },
                set: { document.setShowMirror($0 == 1) }
            )) {
                Text(t("印稿", "Print")).tag(0)
                Text(t("镜像", "Mirror")).tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: locale.usesChinese ? 150 : 168)
            .disabled(document.isDrawingShape)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            Text(document.isDrawingShape ? t("按住拖动绘制外形，松开后自动闭合", "Drag to draw the outline, then release to close it.") : t("拖动文字或图案可以挪位置，方向键微调，Delete 删除", "Drag characters or artwork to move them. Arrow keys nudge, Delete removes."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink.opacity(0.55))
                .lineLimit(2)
            Spacer()
            Text("\(Int(document.project.widthMM.rounded())) × \(Int(document.project.heightMM.rounded())) mm")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink.opacity(0.7))
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private func drawingHint(rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Theme.cinnabar.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func overlay(rect: CGRect) -> some View {
        Canvas { context, _ in
            if document.isDrawingShape, livePoints.count > 1 {
                var path = Path()
                path.move(to: viewPoint(livePoints[0], rect: rect))
                for point in livePoints.dropFirst() {
                    path.addLine(to: viewPoint(point, rect: rect))
                }
                context.stroke(path, with: .color(Theme.cinnabar), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            guard !document.showMirror, !document.isDrawingShape,
                  let element = document.selected else { return }
            let box = selectionBox(element, rect: rect)
            var frame = context
            frame.translateBy(x: box.center.x, y: box.center.y)
            frame.rotate(by: .degrees(element.rotation))
            let local = CGRect(x: -box.size.width / 2, y: -box.size.height / 2, width: box.size.width, height: box.size.height)
            frame.stroke(Path(local), with: .color(Theme.cinnabar), lineWidth: 1)
            let handle = CGRect(x: local.maxX - 4, y: local.maxY - 4, width: 8, height: 8)
            frame.fill(Path(handle), with: .color(Theme.cinnabar))
        }
        .allowsHitTesting(false)
    }

    private func gesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                focused = true
                if document.isDrawingShape {
                    if livePoints.isEmpty {
                        livePoints = [normalized(value.startLocation, rect: rect)]
                    }
                    livePoints.append(normalized(value.location, rect: rect))
                    return
                }
                guard !document.showMirror else { return }
                if drag == nil {
                    drag = beginDrag(at: value.startLocation, rect: rect)
                }
                continueDrag(to: value.location, rect: rect)
            }
            .onEnded { _ in
                if document.isDrawingShape {
                    document.commitFreeform(livePoints)
                    livePoints = []
                }
                drag = nil
            }
    }

    private func beginDrag(at point: CGPoint, rect: CGRect) -> DragAction {
        if let element = document.selected, handleHit(point, element: element, rect: rect) {
            let box = selectionBox(element, rect: rect)
            let distance = max(12, hypot(point.x - box.center.x, point.y - box.center.y))
            let start = element.kind == .text && !element.layout.adjustsScale ? element.fontSize : element.scale
            return .scale(element.id, start: start, center: box.center, startDist: distance)
        }
        let spot = normalized(point, rect: rect)
        if let element = hitTest(spot) {
            document.selectedID = element.id
            return .move(element.id, dx: spot.x - element.x, dy: spot.y - element.y)
        }
        document.selectedID = nil
        return .none
    }

    private func continueDrag(to point: CGPoint, rect: CGRect) {
        switch drag {
        case .move(let id, let dx, let dy):
            let spot = normalized(point, rect: rect)
            guard document.selectedID == id else { return }
            document.updateSelected {
                $0.x = min(1.15, max(-0.15, spot.x - dx))
                $0.y = min(1.15, max(-0.15, spot.y - dy))
            }
        case .scale(_, let start, let center, let startDist):
            let distance = max(8, hypot(point.x - center.x, point.y - center.y))
            let filling = document.selected?.layout == .fill
            let value = min(filling ? 1 : 0.92, max(filling ? 0.55 : 0.08, start * Double(distance / startDist)))
            document.updateSelected { element in
                if element.kind == .text, !element.layout.adjustsScale {
                    element.fontSize = value
                } else {
                    element.scale = min(element.layout == .fill ? 1 : 0.95, value)
                }
            }
        default:
            break
        }
    }

    private func hitTest(_ spot: CGPoint) -> StampElement? {
        for element in document.project.elements.reversed() {
            let size = StampRasterizer.contentSizeMM(element, project: document.project)
            let halfW = size.width / CGFloat(document.project.widthMM) / 2
            let halfH = size.height / CGFloat(document.project.heightMM) / 2
            let dx = spot.x - CGFloat(element.x)
            let dy = spot.y - CGFloat(element.y)
            let angle = CGFloat(-element.rotation) * .pi / 180
            let localX = dx * cos(angle) - dy * sin(angle)
            let localY = dx * sin(angle) + dy * cos(angle)
            if abs(localX) <= halfW, abs(localY) <= halfH { return element }
        }
        return nil
    }

    private func handleHit(_ point: CGPoint, element: StampElement, rect: CGRect) -> Bool {
        let box = selectionBox(element, rect: rect)
        let angle = CGFloat(element.rotation) * .pi / 180
        let lx = box.size.width / 2
        let ly = box.size.height / 2
        let cosine = cos(angle)
        let sine = sin(angle)
        let hx = box.center.x + lx * cosine - ly * sine
        let hy = box.center.y + lx * sine + ly * cosine
        return hypot(point.x - hx, point.y - hy) < 12
    }

    private func selectionBox(_ element: StampElement, rect: CGRect) -> (center: CGPoint, size: CGSize) {
        let sizeMM = StampRasterizer.contentSizeMM(element, project: document.project)
        let center = viewPoint(CGPoint(x: element.x, y: element.y), rect: rect)
        let size = CGSize(
            width: sizeMM.width / document.project.widthMM * rect.width,
            height: sizeMM.height / document.project.heightMM * rect.height
        )
        return (center, size)
    }

    private func stampRect(in size: CGSize) -> CGRect {
        let margin: CGFloat = 36
        let avail = CGSize(width: max(40, size.width - margin * 2), height: max(40, size.height - 12))
        let aspect = document.project.widthMM / document.project.heightMM
        var width = avail.width
        var height = width / aspect
        if height > avail.height {
            height = avail.height
            width = height * aspect
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func normalized(_ point: CGPoint, rect: CGRect) -> CGPoint {
        CGPoint(
            x: (point.x - rect.minX) / max(1, rect.width),
            y: (point.y - rect.minY) / max(1, rect.height)
        )
    }

    private func viewPoint(_ point: CGPoint, rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}

private enum DragAction {
    case none
    case move(UUID, dx: Double, dy: Double)
    case scale(UUID, start: Double, center: CGPoint, startDist: CGFloat)
}
