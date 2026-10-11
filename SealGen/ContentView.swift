import SwiftUI

struct ContentView: View {
    @Environment(\.locale) private var locale
    @State private var document = StampDocument()
    @State private var preset: CameraPreset = .iso
    @State private var cameraTick = 0

    private func t(_ chinese: String, _ english: String) -> String {
        locale.text(chinese, english)
    }

    var body: some View {
        HStack(spacing: 0) {
            InspectorView(document: document)
                .frame(width: 318)
            Rectangle().fill(Theme.line).frame(width: 1)
            DesignCanvasView(document: document)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Theme.line).frame(width: 1)
            preview
                .frame(width: 430)
        }
        .frame(minWidth: 1120, minHeight: 720)
        .background(Theme.sidebar)
        .preferredColorScheme(.dark)
        .task { document.kickoff() }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("立体印章", "Solid seal"))
                    .font(.custom("STSongti-SC-Regular", size: 22))
                    .foregroundStyle(Theme.cream)
                Text(t("印面已左右镜像。拖动旋转，滚轮缩放，右键平移。", "The face is mirrored left to right. Drag to turn, scroll to zoom, right-drag to pan."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScenePreview(mesh: document.sharedMesh, stone: document.stone, cameraTick: cameraTick, preset: preset)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach(CameraPreset.allCases) { item in
                    Button(item.label) {
                        preset = item
                        cameraTick += 1
                    }
                    .buttonStyle(ChipStyle(on: preset == item))
                }
            }
            HStack(spacing: 6) {
                ForEach(StoneColor.allCases) { stone in
                    Button(stone.label) { document.stone = stone }
                        .buttonStyle(ChipStyle(on: document.stone == stone))
                }
            }
            Text(document.isBuilding ? t("正在生成立体模型…", "Building the solid…") : document.status)
                .font(.system(size: 12))
                .foregroundStyle(Theme.gold)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button(t("导出 STL", "Export STL")) { document.exportMesh(.stl) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cinnabar)
                Button(t("导出 3MF", "Export 3MF")) { document.exportMesh(.threeMF) }
                    .buttonStyle(.bordered)
                Button(t("导出 OBJ", "Export OBJ")) { document.exportMesh(.obj) }
                    .buttonStyle(.bordered)
            }
            Button(t("导出印稿 PNG", "Export PNG")) { document.exportImpression() }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.cream.opacity(0.85))
            Text(t("单位是毫米，印面朝上。STL、3MF、OBJ 可直接用 Cura、Bambu Studio、PrusaSlicer 打开。", "Units are millimeters, face up. STL, 3MF, and OBJ open in Cura, Bambu Studio, and PrusaSlicer."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Theme.sidebar)
    }
}
