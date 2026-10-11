import AppKit
import Observation
import UniformTypeIdentifiers

final class SharedMesh {
    let mesh: StampMesh
    init(_ mesh: StampMesh) { self.mesh = mesh }
}

@MainActor
@Observable
final class StampDocument {
    var project = StampProject.sample
    var baseMM = 8.0
    var reliefMM = 1.2
    var handleOn = false
    var handleMM = 16.0
    var handleScale = 0.62
    var resolution = 280.0
    var stone: StoneColor = .cinnabar
    var selectedID: UUID?
    var isDrawingShape = false
    var showMirror = false
    var impression: NSImage?
    var sharedMesh: SharedMesh?
    var isBuilding = false
    var status = UIText.text("正在准备印稿", "Preparing the impression")

    private var looping = false
    private var dirtyPreview = false
    private var dirtyMesh = false
    private var started = false

    var selected: StampElement? {
        project.elements.first { $0.id == selectedID }
    }

    func kickoff() {
        guard !started else { return }
        started = true
        schedule()
    }

    func schedule() {
        dirtyPreview = true
        dirtyMesh = true
        pump()
    }

    func setShowMirror(_ value: Bool) {
        showMirror = value
        dirtyPreview = true
        pump()
    }

    func apply(_ body: (inout StampProject) -> Void) {
        var next = project
        body(&next)
        next.normalize()
        project = next
        schedule()
    }

    func selectShape(_ shape: StampShape) {
        apply { $0.shape = shape }
        if shape == .free, project.freePoints.count < 3 {
            isDrawingShape = true
            showMirror = false
        } else if shape != .free {
            isDrawingShape = false
        }
    }

    func setWidth(_ value: Double) {
        apply { project in
            project.widthMM = value
            if project.shape == .circle { project.heightMM = value }
        }
    }

    func setHeight(_ value: Double) {
        apply { project in
            if project.shape == .circle {
                project.widthMM = value
            } else {
                project.heightMM = value
            }
        }
    }

    func setSize(_ value: Double) {
        apply {
            $0.widthMM = value
            $0.heightMM = value
        }
    }

    func updateSelected(_ body: (inout StampElement) -> Void) {
        guard let id = selectedID, let index = project.elements.firstIndex(where: { $0.id == id }) else { return }
        apply { body(&$0.elements[index]) }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        apply { $0.elements.removeAll { $0.id == id } }
        selectedID = nil
    }

    func nudge(dxMM: Double, dyMM: Double) {
        updateSelected { element in
            element.x = min(1.2, max(-0.2, element.x + dxMM / project.widthMM))
            element.y = min(1.2, max(-0.2, element.y + dyMM / project.heightMM))
        }
    }

    func moveLayer(id: UUID, towardFront: Bool) {
        apply { project in
            guard let index = project.elements.firstIndex(where: { $0.id == id }) else { return }
            let next = index + (towardFront ? 1 : -1)
            guard project.elements.indices.contains(next) else { return }
            project.elements.swapAt(index, next)
        }
    }

    func addText(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var element = StampElement.makeText(text.isEmpty ? "印" : text)
        element.x = 0.5
        element.y = 0.5
        apply { $0.elements.append(element) }
        selectedID = element.id
    }

    func addPattern(_ kind: PatternKind) {
        var element = StampElement.makePattern(kind)
        let slot = project.elements.count
        element.x = 0.5 + Double((slot % 3) - 1) * 0.16
        element.y = 0.62
        apply { $0.elements.append(element) }
        selectedID = element.id
    }

    func addImage(data: Data) {
        guard let image = NSImage(data: data), image.size.height > 1 else {
            status = UIText.text("无法读取这张图片", "Could not read this image")
            return
        }
        var element = StampElement.makeImage(data: data, aspect: image.size.width / image.size.height)
        element.y = 0.5
        apply { $0.elements.append(element) }
        selectedID = element.id
    }

    func commitFreeform(_ raw: [CGPoint]) {
        let decimated = PathSmooth.decimate(raw, minDist: 0.012)
        var points = PathSmooth.rdpClosed(decimated, epsilon: 0.008)
        guard points.count >= 3 else {
            status = UIText.text("笔画太短，请按住拖动画一圈", "The stroke is too short. Drag a full loop.")
            return
        }
        points = PathSmooth.chaikinClosed(points, iterations: 2).map {
            CGPoint(x: min(0.985, max(0.015, $0.x)), y: min(0.985, max(0.015, $0.y)))
        }
        let width = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
        let height = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
        guard width > 0.08, height > 0.08 else {
            status = UIText.text("外形太小，请画得更大一些", "The outline is too small. Draw it larger.")
            return
        }
        apply {
            $0.shape = .free
            $0.freePoints = points
        }
        isDrawingShape = false
    }

    func beginDrawing() {
        showMirror = false
        isDrawingShape = true
        if project.shape != .free {
            apply { $0.shape = .free }
        }
    }

    func clearDrawing() {
        apply { $0.freePoints = [] }
        isDrawingShape = true
        showMirror = false
    }

    func restoreSample() {
        project = StampProject.sample
        baseMM = 8
        reliefMM = 1.2
        handleOn = false
        handleMM = 16
        handleScale = 0.62
        resolution = 280
        selectedID = project.elements.first?.id
        isDrawingShape = false
        showMirror = false
        schedule()
    }

    func exportMesh(_ kind: ExportKind) {
        guard let mesh = sharedMesh?.mesh else {
            status = UIText.text("模型还没生成好", "The model is not ready yet")
            return
        }
        let data: Data
        switch kind {
        case .stl: data = MeshExporter.stl(mesh)
        case .obj: data = MeshExporter.obj(mesh)
        case .threeMF: data = MeshExporter.threeMF(mesh)
        }
        save(data, name: "\(exportBase).\(kind.extension)")
    }

    func exportImpression() {
        let raster = StampRasterizer.rasterize(project: project, longSide: 1400, mirror: false)
        let image = StampRasterizer.colorize(raster, yang: project.mode == .yang)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            status = UIText.text("印稿导出失败", "Could not export the impression")
            return
        }
        save(data, name: "\(exportBase)_\(UIText.text("印稿", "impression")).png")
    }

    private var exportBase: String {
        let mode = project.mode == .yang ? UIText.text("阳刻", "Relief") : UIText.text("阴刻", "Intaglio")
        return "\(UIText.text("印章", "Seal"))_\(mode)_\(Int(project.widthMM.rounded()))x\(Int(project.heightMM.rounded()))mm"
    }

    private func save(_ data: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.title = UIText.text("导出印章", "Export Seal")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try data.write(to: url)
            let kb = Double(data.count) / 1024
            status = kb > 1024
                ? String(format: UIText.text("已导出 %@（%.1f MB）", "Exported %@ (%.1f MB)"), url.lastPathComponent, kb / 1024)
                : String(format: UIText.text("已导出 %@（%.0f KB）", "Exported %@ (%.0f KB)"), url.lastPathComponent, kb)
        } catch {
            status = String(format: UIText.text("导出失败：%@", "Export failed: %@"), error.localizedDescription)
        }
    }

    private func pump() {
        guard !looping else { return }
        looping = true
        Task { @MainActor in
            while self.dirtyPreview || self.dirtyMesh {
                try? await Task.sleep(nanoseconds: 60_000_000)
                if self.dirtyPreview {
                    self.dirtyPreview = false
                    self.rebuildPreview()
                }
                if self.dirtyMesh {
                    self.dirtyMesh = false
                    let input = self.makeMeshInput()
                    self.isBuilding = true
                    let built = await Task.detached(priority: .userInitiated) {
                        StampMeshBuilder.build(input)
                    }.value
                    self.isBuilding = false
                    if let built {
                        self.sharedMesh = SharedMesh(built)
                        self.status = self.summary(built)
                    } else {
                        self.sharedMesh = nil
                        self.status = UIText.text("外形为空，先画好印面轮廓", "Draw the face outline first")
                    }
                }
            }
            self.looping = false
            if self.dirtyPreview || self.dirtyMesh { self.pump() }
        }
    }

    private func rebuildPreview() {
        let raster = StampRasterizer.rasterize(project: project, longSide: 880, mirror: showMirror)
        impression = StampRasterizer.colorize(raster, yang: project.mode == .yang)
    }

    private func makeMeshInput() -> MeshInput {
        let size = StampRasterizer.pixelSize(project: project, longSide: Int(resolution.rounded()))
        let raster = StampRasterizer.rasterize(
            project: project, width: size.width, height: size.height, mirror: true
        )
        return MeshInput(
            mask: raster.mask,
            design: raster.design,
            width: raster.width,
            height: raster.height,
            pitch: Float(size.pitch),
            yang: project.mode == .yang,
            base: Float(max(2, baseMM)),
            relief: Float(max(0.3, reliefMM)),
            handleDepth: handleOn ? Float(max(4, handleMM)) : 0,
            handleScale: Float(min(0.9, max(0.3, handleScale)))
        )
    }

    private func summary(_ mesh: StampMesh) -> String {
        let size = mesh.size
        return String(
            format: UIText.text("印体 %.1f × %.1f × %.1f mm · %@ 个三角面", "Body %.1f × %.1f × %.1f mm · %@ triangles"),
            size.x, size.y, size.z, mesh.triangleCount.formatted()
        )
    }
}

enum ExportKind {
    case stl, obj, threeMF
    var `extension`: String {
        switch self {
        case .stl: "stl"
        case .obj: "obj"
        case .threeMF: "3mf"
        }
    }
}
