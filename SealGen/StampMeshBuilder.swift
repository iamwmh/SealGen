import Foundation
import simd

struct MeshInput: Sendable {
    var mask: [UInt8]
    var design: [UInt8]
    var width: Int
    var height: Int
    var pitch: Float
    var yang: Bool
    var base: Float
    var relief: Float
    var handleDepth: Float
    var handleScale: Float
    var handleMaskOverride: [UInt8]? = nil
}

struct StampMesh: Sendable {
    var id = UUID()
    var positions: [Float]
    var normals: [Float]
    var triangleCount: Int
    var minBound: SIMD3<Float>
    var maxBound: SIMD3<Float>

    var size: SIMD3<Float> { maxBound - minBound }

    func signedVolume() -> Float {
        var volume: Float = 0
        var i = 0
        while i + 8 < positions.count {
            let a = SIMD3<Float>(positions[i], positions[i + 1], positions[i + 2])
            let b = SIMD3<Float>(positions[i + 3], positions[i + 4], positions[i + 5])
            let c = SIMD3<Float>(positions[i + 6], positions[i + 7], positions[i + 8])
            volume += simd_dot(a, simd_cross(b, c))
            i += 9
        }
        return volume / 6
    }
}

enum StampMeshBuilder {
    /// Z-up solid. The printing face points toward +Z so a slicer lays the back on the bed.
    static func build(_ input: MeshInput) -> StampMesh? {
        let w = input.width
        let h = input.height
        let n = w * h
        guard w >= 2, h >= 2, input.mask.count == n, input.design.count == n, input.pitch > 0 else { return nil }

        let base = max(0.4, input.base)
        let relief = max(0, input.relief)
        let pitch = input.pitch
        var present = [Bool](repeating: false, count: n)
        var topZ = [Float](repeating: 0, count: n)
        var botZ = [Float](repeating: 0, count: n)

        let requestedHandle = input.handleDepth > 0.2 && (input.handleMaskOverride != nil || input.handleScale > 0.05)
        var handleCount = 0
        var faceCount = 0

        func faceHeight(ink: Bool) -> Float {
            if input.yang { return ink ? base + relief : base }
            return ink ? base : base + relief
        }

        for j in 0..<h {
            for i in 0..<w {
                let idx = j * w + i
                guard input.mask[idx] > 127 else { continue }
                present[idx] = true
                faceCount += 1
                var isHandle = false
                if requestedHandle {
                    if let override = input.handleMaskOverride, override.count == n {
                        isHandle = override[idx] > 127
                    } else {
                        let sx = (Float(i) + 0.5 - Float(w) / 2) / input.handleScale + Float(w) / 2
                        let sy = (Float(j) + 0.5 - Float(h) / 2) / input.handleScale + Float(h) / 2
                        let ix = Int(sx.rounded(.down))
                        let iy = Int(sy.rounded(.down))
                        if ix >= 0, iy >= 0, ix < w, iy < h, input.mask[iy * w + ix] > 127 {
                            isHandle = true
                        }
                    }
                }
                if isHandle { handleCount += 1 }
                let face = faceHeight(ink: input.design[idx] > 127)
                let lift: Float = requestedHandle ? input.handleDepth : 0
                botZ[idx] = isHandle ? 0 : lift
                topZ[idx] = lift + face
            }
        }
        guard faceCount >= 4 else { return nil }

        if requestedHandle && handleCount == 0 {
            for idx in 0..<n where present[idx] {
                topZ[idx] -= input.handleDepth
                botZ[idx] = 0
            }
        }

        // A 2×2 checkerboard leaves two columns touching only at a corner.
        // That vertex belongs to two separate fans, which Bambu Studio reports
        // as non-manifold. Bridge one orthogonal neighbor so the columns share an edge.
        resolveDiagonalContacts(&present, &botZ, &topZ, width: w, height: h, yang: input.yang)

        func xEdge(_ i: Int) -> Float { (Float(i) - Float(w) * 0.5) * pitch }
        func yEdge(_ j: Int) -> Float { (Float(h) * 0.5 - Float(j)) * pitch }

        var mesh = TriangleSink()
        mesh.reserve(faceCount * 8)

        for j in 0..<h {
            for i in 0..<w {
                let idx = j * w + i
                guard present[idx] else { continue }
                let x0 = xEdge(i)
                let x1 = xEdge(i + 1)
                let y1 = yEdge(j)
                let y0 = yEdge(j + 1)
                let bot = botZ[idx]
                let top = topZ[idx]
                guard top > bot + 1e-4 else { continue }
                mesh.tri(SIMD3(x0, y0, top), SIMD3(x1, y0, top), SIMD3(x1, y1, top))
                mesh.tri(SIMD3(x0, y0, top), SIMD3(x1, y1, top), SIMD3(x0, y1, top))
                mesh.tri(SIMD3(x0, y0, bot), SIMD3(x1, y1, bot), SIMD3(x1, y0, bot))
                mesh.tri(SIMD3(x0, y0, bot), SIMD3(x0, y1, bot), SIMD3(x1, y1, bot))
            }
        }

        func cellZ(_ i: Int, _ j: Int) -> (Bool, Float, Float) {
            guard i >= 0, j >= 0, i < w, j < h else { return (false, 0, 0) }
            let idx = j * w + i
            guard present[idx] else { return (false, 0, 0) }
            return (true, botZ[idx], topZ[idx])
        }

        /// Ranges where exactly one side is solid. `towardB` points from A toward B.
        func intervals(aOn: Bool, aBot: Float, aTop: Float, bOn: Bool, bBot: Float, bTop: Float) -> [(Float, Float, Bool)] {
            var out: [(Float, Float, Bool)] = []
            if aOn && !bOn {
                out.append((aBot, aTop, true))
            } else if bOn && !aOn {
                out.append((bBot, bTop, false))
            } else if aOn && bOn {
                if aTop > bTop + 1e-4 { out.append((bTop, aTop, true)) }
                if bTop > aTop + 1e-4 { out.append((aTop, bTop, false)) }
                if aBot < bBot - 1e-4 { out.append((aBot, bBot, true)) }
                if bBot < aBot - 1e-4 { out.append((bBot, aBot, false)) }
            }
            return out
        }

        /// Every wall is split at the same handful of heights (base, relief, handle).
        /// Adjacent and perpendicular walls then share vertices. Scanning every pixel
        /// would repeat those same few values tens of thousands of times.
        var levels: [Float] = []
        func remember(_ z: Float) {
            if levels.allSatisfy({ abs($0 - z) > 1e-3 }) { levels.append(z) }
        }
        for idx in 0..<n where present[idx] {
            remember(botZ[idx])
            remember(topZ[idx])
        }
        levels.sort()

        func splitLevels(_ z0: Float, _ z1: Float) -> [Float] {
            var bands: [Float] = []
            bands.reserveCapacity(levels.count + 2)
            bands.append(z0)
            for z in levels where z > z0 + 1e-4 && z < z1 - 1e-4 {
                bands.append(z)
            }
            bands.append(z1)
            return bands
        }

        for i in 0...w {
            let x = xEdge(i)
            for j in 0..<h {
                let l = cellZ(i - 1, j)
                let r = cellZ(i, j)
                let y0 = yEdge(j + 1)
                let y1 = yEdge(j)
                for (z0, z1, towardRight) in intervals(aOn: l.0, aBot: l.1, aTop: l.2, bOn: r.0, bBot: r.1, bTop: r.2) {
                    let bands = splitLevels(z0, z1)
                    for k in 0..<(bands.count - 1) {
                        let za = bands[k]
                        let zb = bands[k + 1]
                        if towardRight {
                            mesh.tri(SIMD3(x, y0, za), SIMD3(x, y1, za), SIMD3(x, y1, zb))
                            mesh.tri(SIMD3(x, y0, za), SIMD3(x, y1, zb), SIMD3(x, y0, zb))
                        } else {
                            mesh.tri(SIMD3(x, y1, za), SIMD3(x, y0, za), SIMD3(x, y0, zb))
                            mesh.tri(SIMD3(x, y1, za), SIMD3(x, y0, zb), SIMD3(x, y1, zb))
                        }
                    }
                }
            }
        }

        for j in 0...h {
            let y = yEdge(j)
            for i in 0..<w {
                let lo = cellZ(i, j)
                let hi = cellZ(i, j - 1)
                let x0 = xEdge(i)
                let x1 = xEdge(i + 1)
                for (z0, z1, towardHi) in intervals(aOn: lo.0, aBot: lo.1, aTop: lo.2, bOn: hi.0, bBot: hi.1, bTop: hi.2) {
                    let bands = splitLevels(z0, z1)
                    for k in 0..<(bands.count - 1) {
                        let za = bands[k]
                        let zb = bands[k + 1]
                        if towardHi {
                            mesh.tri(SIMD3(x1, y, za), SIMD3(x0, y, za), SIMD3(x0, y, zb))
                            mesh.tri(SIMD3(x1, y, za), SIMD3(x0, y, zb), SIMD3(x1, y, zb))
                        } else {
                            mesh.tri(SIMD3(x0, y, za), SIMD3(x1, y, za), SIMD3(x1, y, zb))
                            mesh.tri(SIMD3(x0, y, za), SIMD3(x1, y, zb), SIMD3(x0, y, zb))
                        }
                    }
                }
            }
        }

        guard mesh.tris > 0 else { return nil }
        return StampMesh(
            positions: mesh.positions,
            normals: mesh.normals,
            triangleCount: mesh.tris,
            minBound: mesh.minB,
            maxBound: mesh.maxB
        )
    }

    static func selfTest() -> [String] {
        var failures: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures.append(detail.isEmpty ? name : "\(name): \(detail)") }
        }

        func solid(w: Int, h: Int, design: [UInt8] = [], yang: Bool = true, base: Float = 1, relief: Float = 0, handle: Float = 0, scale: Float = 1, override: [UInt8]? = nil, pitch: Float = 1) -> StampMesh? {
            let n = w * h
            let ink = design.isEmpty ? [UInt8](repeating: 0, count: n) : design
            return build(MeshInput(
                mask: [UInt8](repeating: 255, count: n),
                design: ink,
                width: w, height: h, pitch: pitch,
                yang: yang, base: base, relief: relief,
                handleDepth: handle, handleScale: scale,
                handleMaskOverride: override
            ))
        }

        if let cube = solid(w: 1, h: 1, base: 2) {
            // 1×1 is rejected (< 4 pixels). Expected.
            _ = cube
        }
        let block = solid(w: 4, h: 4, base: 2, relief: 0)
        check("block exists", block != nil)
        if let block {
            let volume = block.signedVolume()
            check("block volume", abs(volume - 32) < 0.05, "got \(volume)")
            check("block size", abs(block.size.x - 4) < 0.01 && abs(block.size.y - 4) < 0.01 && abs(block.size.z - 2) < 0.01, "\(block.size)")
            check("block sits on bed", abs(block.minBound.z) < 0.001, "minZ \(block.minBound.z)")
            check("block manifold", manifoldIssues(block) == 0, "open \(manifoldIssues(block))")
        }

        var design = [UInt8](repeating: 0, count: 16)
        design[0] = 255
        if let yang = solid(w: 4, h: 4, design: design, yang: true, base: 2, relief: 1) {
            let volume = yang.signedVolume()
            check("yang volume", abs(volume - 33) < 0.08, "got \(volume)")
            check("yang peak", abs(yang.maxBound.z - 3) < 0.01, "\(yang.maxBound.z)")
            check("yang manifold", manifoldIssues(yang) == 0, "open \(manifoldIssues(yang))")
        } else {
            check("yang exists", false)
        }

        if let yin = solid(w: 4, h: 4, design: design, yang: false, base: 2, relief: 1) {
            let volume = yin.signedVolume()
            check("yin volume", abs(volume - 47) < 0.08, "got \(volume)")
            check("yin manifold", manifoldIssues(yin) == 0, "open \(manifoldIssues(yin))")
        } else {
            check("yin exists", false)
        }

        var handle = [UInt8](repeating: 0, count: 16)
        for j in 1...2 {
            for i in 1...2 { handle[j * 4 + i] = 255 }
        }
        if let gripped = solid(w: 4, h: 4, base: 4, relief: 0, handle: 3, override: handle) {
            let volume = gripped.signedVolume()
            check("handle volume", abs(volume - 76) < 0.15, "got \(volume)")
            check("handle min", abs(gripped.minBound.z) < 0.001)
            check("handle height", abs(gripped.maxBound.z - 7) < 0.05, "\(gripped.maxBound.z)")
            check("handle manifold", manifoldIssues(gripped) == 0, "open \(manifoldIssues(gripped))")
        } else {
            check("handle exists", false)
        }

        var disk = [UInt8](repeating: 0, count: 12 * 12)
        for j in 0..<12 {
            for i in 0..<12 {
                let dx = Float(i) + 0.5 - 6
                let dy = Float(j) + 0.5 - 6
                if dx * dx + dy * dy <= 25 { disk[j * 12 + i] = 255 }
            }
        }
        if let round = build(MeshInput(
            mask: disk, design: [UInt8](repeating: 0, count: 144),
            width: 12, height: 12, pitch: 0.5,
            yang: true, base: 3, relief: 0.8,
            handleDepth: 0, handleScale: 0.6
        )) {
            check("disk manifold", manifoldIssues(round) == 0, "open \(manifoldIssues(round))")
            check("disk positive", round.signedVolume() > 1)
        } else {
            check("disk exists", false)
        }

        var diagonal = [UInt8](repeating: 0, count: 16)
        diagonal[0] = 255
        diagonal[5] = 255
        if let bridged = solid(w: 4, h: 4, design: diagonal, yang: true, base: 2, relief: 1) {
            check("diagonal manifold", manifoldIssues(bridged) == 0, "open \(manifoldIssues(bridged))")
            let volume = bridged.signedVolume()
            check("diagonal bridged", volume > 34.5, "got \(volume)")
        } else {
            check("diagonal exists", false)
        }

        return failures
    }

    /// Join height columns that touch only at a corner. Material is only added:
    /// raised strokes gain a one-pixel fillet, recessed strokes gain a one-pixel bridge,
    /// and the silhouette grows rather than being notched.
    private static func resolveDiagonalContacts(
        _ present: inout [Bool],
        _ botZ: inout [Float],
        _ topZ: inout [Float],
        width w: Int,
        height h: Int,
        yang: Bool
    ) {
        let n = w * h
        func occupied(_ idx: Int, _ z: Float) -> Bool {
            present[idx] && z > botZ[idx] + 1e-4 && z < topZ[idx] - 1e-4
        }
        func conflictZ(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Float? {
            var marks: [Float] = []
            marks.reserveCapacity(8)
            for idx in [a, b, c, d] where present[idx] {
                marks.append(botZ[idx])
                marks.append(topZ[idx])
            }
            guard marks.count >= 2 else { return nil }
            marks.sort()
            var previous = marks[0]
            for z in marks.dropFirst() {
                if z > previous + 1e-4 {
                    let mid = (previous + z) * 0.5
                    let oa = occupied(a, mid)
                    let ob = occupied(b, mid)
                    let oc = occupied(c, mid)
                    let od = occupied(d, mid)
                    if oa == od, ob == oc, oa != ob { return mid }
                }
                previous = z
            }
            return nil
        }
        func copyColumn(_ source: Int, _ target: Int) {
            present[target] = true
            botZ[target] = botZ[source]
            topZ[target] = topZ[source]
        }
        for _ in 0..<12 {
            var changed = false
            if h < 2 || w < 2 { break }
            for j in 0..<(h - 1) {
                for i in 0..<(w - 1) {
                    let a = j * w + i
                    let b = a + 1
                    let c = a + w
                    let d = c + 1
                    guard a < n, d < n, let z = conflictZ(a, b, c, d) else { continue }
                    let pairs = [(a, b), (a, c), (b, d), (c, d)]
                    for (u, v) in pairs {
                        let ou = occupied(u, z)
                        let ov = occupied(v, z)
                        guard ou != ov else { continue }
                        let raised = ou ? u : v
                        let other = ou ? v : u
                        if !present[other] || yang {
                            copyColumn(raised, other)
                        } else {
                            copyColumn(other, raised)
                        }
                        changed = true
                        break
                    }
                }
            }
            if !changed { break }
        }
    }

    static func manifoldIssues(_ mesh: StampMesh) -> Int {
        struct Quant: Hashable {
            let x: Int32, y: Int32, z: Int32
            init(_ v: SIMD3<Float>) {
                x = Int32((v.x * 1000).rounded())
                y = Int32((v.y * 1000).rounded())
                z = Int32((v.z * 1000).rounded())
            }
        }
        struct Edge: Hashable {
            let a: Quant, b: Quant
            init(_ p: SIMD3<Float>, _ q: SIMD3<Float>) {
                let qa = Quant(p)
                let qb = Quant(q)
                if (qa.x, qa.y, qa.z) <= (qb.x, qb.y, qb.z) {
                    a = qa; b = qb
                } else {
                    a = qb; b = qa
                }
            }
        }
        var counts: [Edge: Int] = [:]
        var i = 0
        let p = mesh.positions
        while i + 8 < p.count {
            let a = SIMD3<Float>(p[i], p[i + 1], p[i + 2])
            let b = SIMD3<Float>(p[i + 3], p[i + 4], p[i + 5])
            let c = SIMD3<Float>(p[i + 6], p[i + 7], p[i + 8])
            counts[Edge(a, b), default: 0] += 1
            counts[Edge(b, c), default: 0] += 1
            counts[Edge(c, a), default: 0] += 1
            i += 9
        }
        return counts.values.filter { $0 != 2 }.count
    }
}

private struct TriangleSink {
    var positions: [Float] = []
    var normals: [Float] = []
    var tris = 0
    var minB = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var maxB = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

    mutating func reserve(_ triangles: Int) {
        positions.reserveCapacity(triangles * 9)
        normals.reserveCapacity(triangles * 9)
    }

    mutating func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        guard len > 1e-10 else { return }
        let nn = n / len
        push(a, nn)
        push(b, nn)
        push(c, nn)
        tris += 1
    }

    mutating func push(_ p: SIMD3<Float>, _ n: SIMD3<Float>) {
        positions.append(p.x)
        positions.append(p.y)
        positions.append(p.z)
        normals.append(n.x)
        normals.append(n.y)
        normals.append(n.z)
        minB = simd_min(minB, p)
        maxB = simd_max(maxB, p)
    }
}
