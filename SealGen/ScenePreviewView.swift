import SceneKit
import SwiftUI

enum CameraPreset: String, CaseIterable, Identifiable {
    case iso, top, front, side
    var id: String { rawValue }
    var label: String {
        switch self {
        case .iso: UIText.text("斜视", "Angle")
        case .top: UIText.text("俯视", "Top")
        case .front: UIText.text("正面", "Front")
        case .side: UIText.text("侧面", "Side")
        }
    }
}

struct ScenePreview: NSViewRepresentable {
    var mesh: SharedMesh?
    var stone: StoneColor
    var cameraTick: Int
    var preset: CameraPreset

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(srgbRed: 0.09, green: 0.07, blue: 0.06, alpha: 1)
        let scene = SCNScene()
        view.scene = scene

        func directional(intensity: CGFloat, color: NSColor, angles: SCNVector3) -> SCNNode {
            let node = SCNNode()
            let light = SCNLight()
            light.type = .directional
            light.intensity = intensity
            light.color = color
            node.light = light
            node.eulerAngles = angles
            return node
        }

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 160
        ambientLight.color = NSColor(srgbRed: 1, green: 0.93, blue: 0.88, alpha: 1)
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)
        scene.rootNode.addChildNode(directional(
            intensity: 980,
            color: NSColor(srgbRed: 1, green: 0.96, blue: 0.92, alpha: 1),
            angles: SCNVector3(-1.05, 0.45, 0)
        ))
        scene.rootNode.addChildNode(directional(
            intensity: 260,
            color: NSColor(white: 0.85, alpha: 1),
            angles: SCNVector3(-0.25, -1.5, 0)
        ))
        scene.rootNode.addChildNode(directional(
            intensity: 180,
            color: NSColor(srgbRed: 1, green: 0.78, blue: 0.68, alpha: 1),
            angles: SCNVector3(0.55, 2.4, 0)
        ))

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 0.02
        camera.zFar = 4000
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        view.defaultCameraController.interactionMode = .orbitTurntable

        let model = SCNNode()
        model.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(model)

        context.coordinator.camera = cameraNode
        context.coordinator.model = model
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.meshID != mesh?.mesh.id {
            coordinator.meshID = mesh?.mesh.id
            if let mesh {
                coordinator.model?.geometry = Self.geometry(mesh.mesh, stone: stone)
            } else {
                coordinator.model?.geometry = nil
            }
            if !coordinator.didFrame, mesh != nil {
                coordinator.didFrame = true
                coordinator.frame(preset: .iso, animated: false)
            }
        } else if coordinator.stone != stone {
            coordinator.model?.geometry?.firstMaterial?.diffuse.contents = Theme.stoneNSColor(stone)
            let specular: CGFloat = stone == .ebony ? 0.55 : 0.32
            coordinator.model?.geometry?.firstMaterial?.specular.contents = NSColor(white: specular, alpha: 1)
        }
        if coordinator.cameraTick != cameraTick {
            coordinator.cameraTick = cameraTick
            coordinator.frame(preset: preset, animated: true)
        }
        coordinator.stone = stone
    }

    private static func geometry(_ mesh: StampMesh, stone: StoneColor) -> SCNGeometry {
        let count = mesh.triangleCount * 3
        let positions = mesh.positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let normals = mesh.normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let vertex = SCNGeometrySource(
            data: positions, semantic: .vertex, vectorCount: count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        let normal = SCNGeometrySource(
            data: normals, semantic: .normal, vectorCount: count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        var indices = [UInt32](repeating: 0, count: count)
        for index in 0..<count { indices[index] = UInt32(index) }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: mesh.triangleCount, bytesPerIndex: 4
        )
        let geometry = SCNGeometry(sources: [vertex, normal], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = Theme.stoneNSColor(stone)
        material.specular.contents = NSColor(white: stone == .ebony ? 0.55 : 0.34, alpha: 1)
        material.shininess = 0.22
        material.lightingModel = .blinn
        material.isDoubleSided = false
        geometry.materials = [material]
        return geometry
    }

    final class Coordinator {
        var camera: SCNNode?
        var model: SCNNode?
        weak var view: SCNView?
        var meshID: UUID?
        var stone: StoneColor = .cinnabar
        var cameraTick = -1
        var didFrame = false

        func frame(preset: CameraPreset, animated: Bool) {
            guard let model, let camera, let geometry = model.geometry else { return }
            let box = geometry.boundingBox
            let local = SCNVector3(
                (box.min.x + box.max.x) * 0.5,
                (box.min.y + box.max.y) * 0.5,
                (box.min.z + box.max.z) * 0.5
            )
            let center = model.convertPosition(local, to: nil)
            let span = max(box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z, 8)
            let position: SCNVector3
            switch preset {
            case .iso:
                position = SCNVector3(center.x + span * 0.95, center.y + span * 1.15, center.z + span * 1.35)
            case .top:
                position = SCNVector3(center.x + span * 0.01, center.y + span * 2.5, center.z + span * 0.18)
            case .front:
                position = SCNVector3(center.x, center.y + span * 0.35, center.z + span * 2.35)
            case .side:
                position = SCNVector3(center.x + span * 2.35, center.y + span * 0.35, center.z)
            }
            let apply = {
                camera.position = position
                camera.look(at: center, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            }
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.35
                apply()
                SCNTransaction.commit()
            } else {
                apply()
            }
            view?.defaultCameraController.target = center
        }
    }
}
