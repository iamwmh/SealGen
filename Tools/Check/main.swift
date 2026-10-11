import AppKit
import Foundation
import ImageIO

let dir = URL(fileURLWithPath: "/tmp/sealgen", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let meshFailures = StampMeshBuilder.selfTest()
if meshFailures.isEmpty {
    print("MESH OK")
} else {
    print("MESH FAILURES")
    for failure in meshFailures { print(" -", failure) }
}

func save(_ image: NSImage, _ name: String) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: dir.appendingPathComponent(name))
}

func render(_ project: StampProject, _ name: String, mirror: Bool = false) {
    let raster = StampRasterizer.rasterize(project: project, longSide: 720, mirror: mirror)
    save(StampRasterizer.colorize(raster, yang: project.mode == .yang), name)
}

var yang = StampProject.sample
render(yang, "yang.png")
render(yang, "yang-mirror.png", mirror: true)

var yin = yang
yin.mode = .yin
render(yin, "yin.png")

var grid = StampProject()
grid.shape = .square
grid.widthMM = 42
grid.heightMM = 42
grid.borderMM = 1.6
grid.mode = .yang
var text = StampElement.makeText("大展宏图")
text.layout = .gridRight
text.fontSize = 0.34
text.bold = true
grid.elements = [text]
render(grid, "grid.png")

var vertical = StampProject()
vertical.shape = .ellipse
vertical.widthMM = 28
vertical.heightMM = 48
vertical.borderMM = 1.2
var vtext = StampElement.makeText("正心")
vtext.layout = .vertical
vtext.fontSize = 0.34
vertical.elements = [vtext]
render(vertical, "vertical.png")

var ring = StampProject()
ring.shape = .circle
ring.borderMM = 1.2
var rtext = StampElement.makeText("福禄寿喜")
rtext.layout = .ring
rtext.fontSize = 0.16
rtext.scale = 0.62
ring.elements = [rtext]
render(ring, "ring.png")

var heart = StampProject()
heart.shape = .heart
heart.borderMM = 1.1
heart.elements = [StampElement.makeText("安")]
render(heart, "heart.png")

var patterns = StampProject()
patterns.shape = .square
patterns.widthMM = 90
patterns.heightMM = 60
patterns.borderMM = 0
patterns.elements = []
let kinds = PatternKind.allCases
let spots: [(Double, Double)] = [(0.18, 0.32), (0.5, 0.32), (0.82, 0.32), (0.18, 0.72), (0.5, 0.72), (0.82, 0.72)]
for (kind, spot) in zip(kinds, spots) {
    var element = StampElement.makePattern(kind)
    element.x = spot.0
    element.y = spot.1
    element.scale = 0.28
    patterns.elements.append(element)
}
render(patterns, "patterns.png")

var rotated = StampProject.sample
rotated.elements[0].rotation = 25
rotated.elements[0].text = "福A"
render(rotated, "rotated.png")

let started = Date()
let size = StampRasterizer.pixelSize(project: yang, longSide: 280)
let raster = StampRasterizer.rasterize(project: yang, width: size.width, height: size.height, mirror: true)
let input = MeshInput(
    mask: raster.mask, design: raster.design, width: size.width, height: size.height,
    pitch: Float(size.pitch), yang: true, base: 8, relief: 1.2, handleDepth: 0, handleScale: 0.6
)
if let mesh = StampMeshBuilder.build(input) {
    let ms = Date().timeIntervalSince(started) * 1000
    let issues = StampMeshBuilder.manifoldIssues(mesh)
    print(String(format: "SAMPLE tris=%d vol=%.1f issues=%d ms=%.0f size=%.2f %.2f %.2f",
                 mesh.triangleCount, mesh.signedVolume(), issues, ms, mesh.size.x, mesh.size.y, mesh.size.z))
    let stl = MeshExporter.stl(mesh)
    let count = stl.subdata(in: 80..<84).withUnsafeBytes { $0.load(as: UInt32.self) }
    print("STL bytes=\(stl.count) tris=\(count) match=\(count == UInt32(mesh.triangleCount))")
    let tmf = MeshExporter.threeMF(mesh)
    print("3MF bytes=\(tmf.count) zip=\(tmf.prefix(2) == Data([0x50, 0x4b]))")
} else {
    print("SAMPLE mesh missing")
}

var filled = StampProject()
filled.shape = .square
filled.widthMM = 40
filled.heightMM = 40
filled.borderMM = 1.6
filled.borderStyle = .meander
var fillText = StampElement.makeText("福禄寿喜")
fillText.layout = .fill
fillText.scale = 0.96
fillText.tracking = 0.1
filled.elements = [fillText]
render(filled, "fill-four.png")

var one = StampProject.sample
one.elements[0].layout = .fill
one.elements[0].scale = 0.98
one.elements[0].tracking = 0.04
render(one, "fill-one.png")

func plaque(_ style: BorderStyle, _ name: String, tall: Bool) {
    var project = StampProject()
    project.shape = tall ? .square : .circle
    project.widthMM = tall ? 30 : 40
    project.heightMM = tall ? 78 : 40
    project.borderMM = 1.8
    project.borderStyle = style
    project.elements = []
    render(project, name)
}
plaque(.sea, "plaque-sea.png", tall: true)

let styles = BorderStyle.allCases
let sheet = StampProject()
var sheetProject = StampProject()
sheetProject.shape = .square
sheetProject.widthMM = 36
sheetProject.heightMM = 36
sheetProject.borderMM = 1.7
sheetProject.elements = []
func sheetImage(_ style: BorderStyle, shape: StampShape) -> NSImage {
    var project = sheetProject
    project.shape = shape
    project.borderStyle = style
    if shape == .ellipse {
        project.widthMM = 48
        project.heightMM = 32
    }
    let raster = StampRasterizer.rasterize(project: project, longSide: 280, mirror: false)
    return StampRasterizer.colorize(raster, yang: true)
}
let cell = 280
let cols = styles.count
let rows = 2
let canvas = NSImage(size: NSSize(width: cols * cell, height: rows * cell))
canvas.lockFocus()
NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: cols * cell, height: rows * cell).fill()
for (index, style) in styles.enumerated() {
    let square = sheetImage(style, shape: .square)
    let round = sheetImage(style, shape: .circle)
    square.draw(in: NSRect(x: index * cell + 8, y: cell + 8, width: cell - 16, height: cell - 16))
    round.draw(in: NSRect(x: index * cell + 8, y: 8, width: cell - 16, height: cell - 16))
}
canvas.unlockFocus()
save(canvas, "borders.png")
_ = sheet

print("PNG dir \(dir.path)")
