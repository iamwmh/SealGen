import Foundation
import simd

enum MeshExporter {
    static func stl(_ mesh: StampMesh) -> Data {
        let count = mesh.triangleCount
        var data = Data()
        data.reserveCapacity(84 + count * 50)
        var header = [UInt8](repeating: 0, count: 80)
        let title = Array("SealGen mirrored stamp. Units: millimeters.".utf8)
        for index in 0..<min(79, title.count) { header[index] = title[index] }
        data.append(contentsOf: header)
        append(UInt32(count), to: &data)
        let p = mesh.positions
        var offset = 0
        for _ in 0..<count {
            let a = SIMD3<Float>(p[offset], p[offset + 1], p[offset + 2])
            let b = SIMD3<Float>(p[offset + 3], p[offset + 4], p[offset + 5])
            let c = SIMD3<Float>(p[offset + 6], p[offset + 7], p[offset + 8])
            var normal = simd_normalize(simd_cross(b - a, c - a))
            if !normal.x.isFinite { normal = SIMD3<Float>(0, 0, 1) }
            append(normal.x, to: &data)
            append(normal.y, to: &data)
            append(normal.z, to: &data)
            append(a.x, to: &data); append(a.y, to: &data); append(a.z, to: &data)
            append(b.x, to: &data); append(b.y, to: &data); append(b.z, to: &data)
            append(c.x, to: &data); append(c.y, to: &data); append(c.z, to: &data)
            append(UInt16(0), to: &data)
            offset += 9
        }
        return data
    }

    static func obj(_ mesh: StampMesh) -> Data {
        var text = "# SealGen stamp\n# units millimeters\n"
        text.reserveCapacity(mesh.triangleCount * 96)
        let p = mesh.positions
        let n = mesh.normals
        var offset = 0
        var index = 1
        var faces = ""
        faces.reserveCapacity(mesh.triangleCount * 32)
        for _ in 0..<mesh.triangleCount {
            for corner in 0..<3 {
                let o = offset + corner * 3
                text += "v \(num(p[o])) \(num(p[o + 1])) \(num(p[o + 2]))\n"
                text += "vn \(num(n[o])) \(num(n[o + 1])) \(num(n[o + 2]))\n"
            }
            faces += "f \(index)//\(index) \(index + 1)//\(index + 1) \(index + 2)//\(index + 2)\n"
            index += 3
            offset += 9
        }
        text += faces
        return Data(text.utf8)
    }

    static func threeMF(_ mesh: StampMesh) -> Data {
        let welded = weld(mesh)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="zh-CN" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
        <metadata name="Application">SealGen</metadata>
        <resources><object id="1" type="model"><mesh><vertices>
        """
        xml.reserveCapacity(welded.vertices.count * 24 + welded.indices.count * 16)
        let v = welded.vertices
        var i = 0
        while i + 2 < v.count {
            xml += "<vertex x=\"\(num(v[i]))\" y=\"\(num(v[i + 1]))\" z=\"\(num(v[i + 2]))\"/>"
            i += 3
        }
        xml += "</vertices><triangles>"
        let idx = welded.indices
        i = 0
        while i + 2 < idx.count {
            xml += "<triangle v1=\"\(idx[i])\" v2=\"\(idx[i + 1])\" v3=\"\(idx[i + 2])\"/>"
            i += 3
        }
        xml += "</triangles></mesh></object></resources><build><item objectid=\"1\"/></build></model>"
        let model = Data(xml.utf8)
        let types = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
        """.utf8)
        let rels = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>
        """.utf8)
        return zipStore([
            ZipEntry(name: "[Content_Types].xml", data: types),
            ZipEntry(name: "_rels/.rels", data: rels),
            ZipEntry(name: "3D/3dmodel.model", data: model),
        ])
    }

    /// Printed from the same 0.000001 mm buckets the welder uses, so the file
    /// text and the triangle indices describe one mesh.
    private static func quant(_ value: Float) -> Int32 {
        Int32((Double(value) * 1_000_000).rounded())
    }

    private static func num(_ value: Float) -> String {
        let scaled = quant(value)
        let sign = scaled < 0 ? "-" : ""
        let absolute = abs(scaled)
        return String(format: "%@%d.%06d", sign, absolute / 1_000_000, absolute % 1_000_000)
    }

    private static func append<T>(_ value: T, to data: inout Data) {
        var value = value
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func weld(_ mesh: StampMesh) -> (vertices: [Float], indices: [UInt32]) {
        struct Key: Hashable {
            let x: Int32, y: Int32, z: Int32
        }
        var map: [Key: UInt32] = [:]
        map.reserveCapacity(mesh.triangleCount)
        var vertices: [Float] = []
        vertices.reserveCapacity(mesh.triangleCount * 3)
        var indices: [UInt32] = []
        indices.reserveCapacity(mesh.triangleCount * 3)
        let p = mesh.positions
        for i in stride(from: 0, to: p.count, by: 3) {
            let key = Key(x: quant(p[i]), y: quant(p[i + 1]), z: quant(p[i + 2]))
            if let existing = map[key] {
                indices.append(existing)
            } else {
                let index = UInt32(vertices.count / 3)
                map[key] = index
                vertices.append(p[i])
                vertices.append(p[i + 1])
                vertices.append(p[i + 2])
                indices.append(index)
            }
        }
        return (vertices, indices)
    }
}

private struct ZipEntry {
    var name: String
    var data: Data
}

private func zipStore(_ entries: [ZipEntry]) -> Data {
    var archive = Data()
    var directory = Data()
    for entry in entries {
        let name = Data(entry.name.utf8)
        let crc = crc32(entry.data)
        let offset = UInt32(archive.count)
        appendLE(UInt32(0x04034b50), to: &archive)
        appendLE(UInt16(20), to: &archive)
        appendLE(UInt16(0), to: &archive)
        appendLE(UInt16(0), to: &archive)
        appendLE(UInt16(0), to: &archive)
        appendLE(UInt16(0), to: &archive)
        appendLE(crc, to: &archive)
        appendLE(UInt32(entry.data.count), to: &archive)
        appendLE(UInt32(entry.data.count), to: &archive)
        appendLE(UInt16(name.count), to: &archive)
        appendLE(UInt16(0), to: &archive)
        archive.append(name)
        archive.append(entry.data)

        appendLE(UInt32(0x02014b50), to: &directory)
        appendLE(UInt16(20), to: &directory)
        appendLE(UInt16(20), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(crc, to: &directory)
        appendLE(UInt32(entry.data.count), to: &directory)
        appendLE(UInt32(entry.data.count), to: &directory)
        appendLE(UInt16(name.count), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(UInt16(0), to: &directory)
        appendLE(UInt32(0), to: &directory)
        appendLE(offset, to: &directory)
        directory.append(name)
    }
    let directoryOffset = UInt32(archive.count)
    archive.append(directory)
    appendLE(UInt32(0x06054b50), to: &archive)
    appendLE(UInt16(0), to: &archive)
    appendLE(UInt16(0), to: &archive)
    appendLE(UInt16(entries.count), to: &archive)
    appendLE(UInt16(entries.count), to: &archive)
    appendLE(UInt32(directory.count), to: &archive)
    appendLE(directoryOffset, to: &archive)
    appendLE(UInt16(0), to: &archive)
    return archive
}

private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFFFFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            let mask = (crc & 1) != 0 ? UInt32(0xEDB88320) : 0
            crc = (crc >> 1) ^ mask
        }
    }
    return crc ^ 0xFFFFFFFF
}
