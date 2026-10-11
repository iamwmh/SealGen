import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    var document: StampDocument
    @Environment(\.locale) private var locale
    @State private var draft = "福"
    @State private var importing = false

    private func t(_ chinese: String, _ english: String) -> String {
        locale.text(chinese, english)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                shapeSection
                sizeSection
                carveSection
                bodySection
                contentSection
                if let element = document.selected {
                    editor(element)
                }
                Button(t("恢复示例", "Restore sample")) { document.restoreSample() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.muted)
                    .font(.system(size: 12))
            }
            .padding(18)
        }
        .background(Theme.sidebar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                document.addImage(data: data)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SealMark(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("印章工坊", "Seal Workshop"))
                    .font(.custom("STSongti-SC-Regular", size: 22))
                    .foregroundStyle(Theme.cream)
                Text(t("阴刻 · 阳刻 · 可打印", "Intaglio and relief, ready to print"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("印面形状", "Face"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: locale.usesChinese ? 64 : 72), spacing: 6)], spacing: 6) {
                ForEach(StampShape.allCases) { shape in
                    Button(shape.label) { document.selectShape(shape) }
                        .buttonStyle(ChipStyle(on: document.project.shape == shape))
                }
            }
            if document.project.shape == .square {
                sliderRow(t("圆角", "Corner"), value: document.project.cornerRadiusMM, range: 0...12, format: "%.1f") { value in
                    document.apply { $0.cornerRadiusMM = value }
                }
            }
            if document.project.shape == .free {
                HStack(spacing: 8) {
                    Button(document.isDrawingShape ? t("正在绘制", "Drawing") : t("重新绘制", "Redraw")) { document.beginDrawing() }
                        .buttonStyle(ChipStyle(on: document.isDrawingShape))
                    Button(t("清除", "Clear")) { document.clearDrawing() }
                        .buttonStyle(ChipStyle(on: false))
                }
            }
        }
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("尺寸（毫米）", "Size (mm)"))
            HStack(spacing: 8) {
                ForEach([25.0, 30, 40, 50], id: \.self) { size in
                    Button("\(Int(size))") { document.setSize(size) }
                        .buttonStyle(ChipStyle(on: abs(document.project.widthMM - size) < 0.1 && abs(document.project.heightMM - size) < 0.1))
                }
            }
            HStack(spacing: 10) {
                numberField(t("宽", "Width"), value: document.project.widthMM) { document.setWidth($0) }
                numberField(t("高", "Height"), value: document.project.heightMM) { document.setHeight($0) }
            }
        }
    }

    private var carveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("刻法", "Carving"))
            HStack(spacing: 8) {
                ForEach(CarveMode.allCases) { mode in
                    Button {
                        document.apply { $0.mode = mode }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title).font(.system(size: 14, weight: .semibold))
                            Text(mode.subtitle).font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(ChipStyle(on: document.project.mode == mode))
                }
            }
            Text(document.project.mode.detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            sectionLabel(t("边框纹饰", "Border"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: locale.usesChinese ? 58 : 76), spacing: 6)], spacing: 6) {
                ForEach(BorderStyle.allCases) { style in
                    Button(style.label) {
                        document.apply { $0.borderStyle = style }
                    }
                    .buttonStyle(ChipStyle(on: document.project.borderStyle == style))
                }
            }
            sliderRow(t("粗细", "Weight"), value: document.project.borderMM, range: 0...6, format: "%.1f") { value in
                document.apply { $0.borderMM = value }
            }
            Text(t("粗细会一起改变线条和纹样大小。阳刻是红线，阴刻是白线。设为 0 就不要边框。", "Weight changes the lines and the ornament together. Relief prints a red line, intaglio a white line. Set it to 0 for no border."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("印体", "Body"))
            sliderRow(t("厚度", "Depth"), value: document.baseMM, range: 3...20, format: "%.1f") { value in
                document.baseMM = value
                document.schedule()
            }
            sliderRow(t("凸起", "Raise"), value: document.reliefMM, range: 0.4...3, format: "%.1f") { value in
                document.reliefMM = value
                document.schedule()
            }
            Toggle(isOn: Binding(
                get: { document.handleOn },
                set: { document.handleOn = $0; document.schedule() }
            )) {
                Text(t("加手柄", "Add a handle")).font(.system(size: 13))
            }
            .toggleStyle(.switch)
            .tint(Theme.cinnabar)
            if document.handleOn {
                sliderRow(t("柄高", "Length"), value: document.handleMM, range: 8...36, format: "%.0f") { value in
                    document.handleMM = value
                    document.schedule()
                }
                sliderRow(t("柄粗", "Girth"), value: document.handleScale, range: 0.38...0.86, format: "%.2f") { value in
                    document.handleScale = value
                    document.schedule()
                }
                Text(t("手柄比印面窄，打印时背面可能需要支撑，印面图案在最上方。", "The handle is narrower than the face. The back may need supports, and the design sits on top."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sliderRow(t("精度", "Detail"), value: document.resolution, range: 140...400, format: "%.0f") { value in
                document.resolution = value
                document.schedule()
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("文字与图案", "Content"))
            HStack(spacing: 8) {
                TextField(t("要刻的字", "Characters"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button(t("添加", "Add")) { document.addText(draft) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cinnabar)
            }
            HStack(spacing: 8) {
                Button(t("添加图片", "Add Image")) { importing = true }
                    .buttonStyle(ChipStyle(on: false))
                Menu {
                    ForEach(PatternKind.allCases) { kind in
                        Button(kind.label) { document.addPattern(kind) }
                    }
                } label: {
                    Text(t("添加纹样", "Add Motif"))
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.sidebarRaised, in: RoundedRectangle(cornerRadius: 8))
            }
            if document.project.elements.isEmpty {
                Text(t("还没有内容。加上文字、图片或纹样。", "Nothing here yet. Add characters, an image, or a motif."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(document.project.elements) { element in
                elementRow(element)
            }
        }
    }

    private func elementRow(_ element: StampElement) -> some View {
        let on = document.selectedID == element.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(element.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(element.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { document.moveLayer(id: element.id, towardFront: true) } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            Button { document.moveLayer(id: element.id, towardFront: false) } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            Button { document.selectedID = element.id; document.deleteSelected() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(on ? Theme.cinnabar.opacity(0.28) : Theme.sidebarRaised, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { document.selectedID = element.id }
    }

    @ViewBuilder
    private func editor(_ element: StampElement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("当前内容", "Selection"))
            switch element.kind {
            case .text:
                TextField(t("文字", "Text"), text: Binding(
                    get: { element.text },
                    set: { value in document.updateSelected { $0.text = value } }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.custom(SealFont.named(element.fontID).heavy, size: 16))
                Picker(t("字体", "Font"), selection: Binding(
                    get: { element.fontID },
                    set: { value in document.updateSelected { $0.fontID = value } }
                )) {
                    ForEach(SealFont.all) { font in
                        Text(font.label).tag(font.id)
                    }
                }
                Picker(t("排版", "Layout"), selection: Binding(
                    get: { element.layout },
                    set: { value in
                        document.updateSelected { item in
                            let previous = item.layout
                            item.layout = value
                            if value == .ring, previous != .ring {
                                item.fontSize = min(item.fontSize, 0.18)
                                item.scale = 0.72
                            }
                            if value == .fill, previous != .fill {
                                item.scale = 0.96
                                item.x = 0.5
                                item.y = 0.5
                                if item.tracking < 0.06 { item.tracking = 0.1 }
                            }
                        }
                    }
                )) {
                    ForEach(TextLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                Toggle(t("粗体", "Bold"), isOn: Binding(
                    get: { element.bold },
                    set: { value in document.updateSelected { $0.bold = value } }
                ))
                .toggleStyle(.switch)
                .tint(Theme.cinnabar)
                if element.layout == .fill {
                    sliderRow(t("铺满", "Fill"), value: element.scale, range: 0.72...1, format: "%.2f") { value in
                        document.updateSelected { $0.scale = value }
                    }
                    sliderRow(t("字缝", "Gap"), value: element.tracking, range: 0...0.36, format: "%.2f") { value in
                        document.updateSelected { $0.tracking = value }
                    }
                    Text(t("文字自动放大，铺满边框里面。多字从右往左竖排；想自己分行，就在文字里换行。", "Characters grow to fill the area inside the border. Several characters run in columns from right to left. Press Return to start a new row."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    sliderRow(t("字号", "Size"), value: element.fontSize, range: 0.08...0.9, format: "%.2f") { value in
                        document.updateSelected { $0.fontSize = value }
                    }
                    if element.layout == .ring {
                        sliderRow(t("环径", "Radius"), value: element.scale, range: 0.35...0.92, format: "%.2f") { value in
                            document.updateSelected { $0.scale = value }
                        }
                    }
                    sliderRow(t("字距", "Spacing"), value: element.tracking, range: -0.08...0.45, format: "%.2f") { value in
                        document.updateSelected { $0.tracking = value }
                    }
                }
                if element.layout == .gridRight {
                    Text(t("田字右起按篆刻习惯：先右列自上而下，再左列。", "The right-hand grid follows seal order: down the right column, then the left."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .image:
                Picker(t("取色", "Ink"), selection: Binding(
                    get: { element.inkMode },
                    set: { value in document.updateSelected { $0.inkMode = value } }
                )) {
                    ForEach(InkMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                sliderRow(t("阈值", "Threshold"), value: element.threshold, range: 0.05...0.95, format: "%.2f") { value in
                    document.updateSelected { $0.threshold = value }
                }
                sliderRow(t("大小", "Scale"), value: element.scale, range: 0.12...0.95, format: "%.2f") { value in
                    document.updateSelected { $0.scale = value }
                }
            case .pattern:
                Picker(t("纹样", "Motif"), selection: Binding(
                    get: { element.pattern },
                    set: { value in document.updateSelected { $0.pattern = value } }
                )) {
                    ForEach(PatternKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                sliderRow(t("大小", "Scale"), value: element.scale, range: 0.12...0.95, format: "%.2f") { value in
                    document.updateSelected { $0.scale = value }
                }
            }
            sliderRow(t("旋转", "Rotate"), value: element.rotation, range: -180...180, format: "%.0f") { value in
                document.updateSelected { $0.rotation = value }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.gold)
            .tracking(1.1)
    }

    private func sliderRow(_ title: String, value: Double, range: ClosedRange<Double>, format: String, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.cream.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: locale.usesChinese ? 36 : 72, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range)
                .tint(Theme.cinnabar)
            Text(String(format: format, value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func numberField(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.cream.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TextField(title, value: Binding(get: { value }, set: set), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: locale.usesChinese ? 72 : 64)
        }
    }
}

struct ChipStyle: ButtonStyle {
    var on: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: on ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(on ? Theme.cream : Theme.cream.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(on ? Theme.cinnabar : Theme.sidebarRaised, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
