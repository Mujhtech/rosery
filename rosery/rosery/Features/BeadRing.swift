import RealityKit
import SwiftUI
import UIKit

/// A real, softly lit strand. The camera is entirely virtual and never starts an AR session.
struct BeadRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    let target: Int
    var wide = false
    var appearance: BeadAppearance = .standard

    var body: some View {
        TasbihSculpture(count: count, wide: wide, dark: colorScheme == .dark,
                       reduceMotion: reduceMotion, appearance: appearance)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TasbihSculpture: UIViewRepresentable {
    let count: Int
    let wide: Bool
    let dark: Bool
    let reduceMotion: Bool
    let appearance: BeadAppearance

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SculptureARView {
        let view = SculptureARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.isOpaque = false
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        view.isUserInteractionEnabled = false
        context.coordinator.install(in: view, count: count, wide: wide, dark: dark, appearance: appearance)
        view.onLayout = { [weak coordinator = context.coordinator] size in
            coordinator?.updateViewport(size)
        }
        return view
    }

    func updateUIView(_ view: SculptureARView, context: Context) {
        context.coordinator.update(count: count, wide: wide, dark: dark,
                                   reduceMotion: reduceMotion, appearance: appearance)
        view.environment.lighting.intensityExponent = dark ? 1.85 : 1.35
    }

    static func dismantleUIView(_ view: SculptureARView, coordinator: Coordinator) {
        view.onLayout = nil
        coordinator.lightingTask?.cancel()
        view.scene.anchors.removeAll()
    }

    @MainActor
    final class Coordinator {
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private var beads: [Entity] = []
        private var lastCount = 0
        private var isWide = false
        private var isDark = false
        private var isAttached = false
        private var viewportSize = CGSize.zero
        private var appearance: BeadAppearance = .standard
        private let key = DirectionalLight()
        private let fill = DirectionalLight()
        private var spindle: ModelEntity?
        private var spindleMeshes: (plain: MeshResource, wood: MeshResource)?
        private var cords: [ModelEntity] = []
        var lightingTask: Task<Void, Never>?

        func install(in view: ARView, count: Int, wide: Bool, dark: Bool, appearance: BeadAppearance) {
            lastCount = count
            isWide = wide
            isDark = dark
            self.appearance = appearance
            camera.camera.fieldOfViewInDegrees = 34
            if #available(iOS 18.0, *) {
                camera.camera.fieldOfViewOrientation = .vertical
            }
            camera.look(at: [0.012, -0.025, 0], from: [0.012, -0.025, wide ? 0.50 : 0.51], relativeTo: nil)
            anchor.addChild(camera)

            // A broad reflected softbox gives the onyx its narrow, curved silver highlights.
            key.light.color = UIColor(red: 1, green: 0.97, blue: 0.91, alpha: 1)
            key.light.intensity = dark ? 4_200 : 2_700
            key.look(at: .zero, from: [-0.4, 0.6, 0.8], relativeTo: nil)
            anchor.addChild(key)
            fill.light.color = UIColor(red: 0.86, green: 0.9, blue: 1, alpha: 1)
            fill.light.intensity = dark ? 2_600 : 1_100
            fill.look(at: .zero, from: [0.5, -0.1, 0.4], relativeTo: nil)
            anchor.addChild(fill)

            let beadMesh = SculptureGeometry.bead(appearance.shape)
            let shadowMaterial: UnlitMaterial?
            if #available(iOS 18.0, *) {
                shadowMaterial = SculptureMaterials.shadow()
            } else {
                // iOS 17 cannot disable material depth writes. Composite the shadows first,
                // so transparent corners cannot hide another bead's shadow.
                shadowMaterial = nil
                if let shadow = SculptureMaterials.combinedShadow() { anchor.addChild(shadow) }
            }
            let shadowMesh = MeshResource.generatePlane(width: 0.036, height: 0.033)
            let stoneMaterials = (0..<3).map { SculptureMaterials.bead(appearance, variation: $0, dark: dark) }
            for index in 0..<33 {
                let holder = Entity()
                holder.name = "prayer-bead-\(index)"
                let bead = ModelEntity(mesh: beadMesh, materials: [stoneMaterials[index % 3]])
                bead.scale = SculptureGeometry.beadScale(appearance.shape, index: index)
                holder.addChild(bead)
                if let shadowMaterial {
                    let shadow = ModelEntity(mesh: shadowMesh, materials: [shadowMaterial])
                    shadow.position = [0.0025, -0.004, -0.019]
                    holder.addChild(shadow)
                }
                if index == 0 {
                    let marker = ModelEntity(mesh: SculptureGeometry.cylinder(height: 0.0015, radius: 0.0033),
                                             materials: [SculptureMaterials.brass])
                    marker.position = [0, 0.0094, 0]
                    bead.addChild(marker)
                }
                anchor.addChild(holder)
                beads.append(holder)
                place(holder, index: index, count: count, animated: false)
            }

            let cordPoints = (0...264).map { Strand.point(at: Float($0) / 264) - SIMD3<Float>(0, 0, 0.002) }
            if let mesh = SculptureGeometry.tubes([(cordPoints, Float(0.00065))]) {
                let cord = ModelEntity(mesh: mesh, materials: [SculptureMaterials.silk(dark: isDark)])
                anchor.addChild(cord)
                cords.append(cord)
            }
            addImame()
            if let environment = SculptureLighting.resource {
                attach(to: view, environment: environment)
            } else if #available(iOS 18.0, *) {
                // Do not render the stones under RealityKit's temporary default illumination.
                // The shared load survives a tab change; only this view's waiter is canceled.
                lightingTask = Task { @MainActor [weak self, weak view] in
                    let environment = await SculptureLighting.load()
                    guard !Task.isCancelled, let self, let view else { return }
                    self.attach(to: view, environment: environment)
                }
            } else {
                attach(to: view, environment: nil)
            }
        }

        private func attach(to view: ARView, environment: EnvironmentResource?) {
            view.environment.lighting.resource = environment
            view.environment.lighting.intensityExponent = isDark ? 1.85 : 1.35
            view.scene.addAnchor(anchor)
            isAttached = true
        }

        func updateViewport(_ size: CGSize) {
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0, size != viewportSize else { return }
            viewportSize = size
            frameCamera()
        }

        private func frameCamera() {
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }
            let aspect = Float(viewportSize.width / viewportSize.height)
            let tangent = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
            // The strand, imame, tassel and contact shadows fit inside this padded
            // 40 × 30 cm frame, including the largest bead shape during a count.
            let verticalDistance: Float = 0.15 / tangent
            let horizontalDistance: Float = 0.20 / (tangent * aspect)
            let distance = max(isWide ? 0.50 : 0.51, max(verticalDistance, horizontalDistance) + 0.025)
            camera.look(at: [0.012, -0.025, 0], from: [0.012, -0.025, distance], relativeTo: nil)
        }

        func update(count: Int, wide: Bool, dark: Bool, reduceMotion: Bool, appearance: BeadAppearance) {
            let lightingChanged = dark != isDark
            let surfaceChanged = lightingChanged || appearance.material != self.appearance.material
                || appearance.color != self.appearance.color
            let shapeChanged = appearance.shape != self.appearance.shape
            if lightingChanged {
                isDark = dark
                key.light.intensity = dark ? 4_200 : 2_700
                fill.light.intensity = dark ? 2_600 : 1_100
                for cord in cords { cord.model?.materials = [SculptureMaterials.silk(dark: dark)] }
            }
            if surfaceChanged {
                let materials = (0..<3).map { SculptureMaterials.bead(appearance, variation: $0, dark: dark) }
                for (index, holder) in beads.enumerated() {
                    (holder.children.first as? ModelEntity)?.model?.materials = [materials[index % 3]]
                }
                spindle?.model?.materials = [materials[1]]
                if let spindleMeshes {
                    spindle?.model?.mesh = appearance.material == .wood ? spindleMeshes.wood : spindleMeshes.plain
                }
            }
            if shapeChanged {
                let mesh = SculptureGeometry.bead(appearance.shape)
                for (index, holder) in beads.enumerated() {
                    guard let stone = holder.children.first as? ModelEntity else { continue }
                    stone.model?.mesh = mesh
                    stone.scale = SculptureGeometry.beadScale(appearance.shape, index: index)
                }
            }
            self.appearance = appearance
            if wide != isWide {
                isWide = wide
                frameCamera()
            }
            guard count != lastCount else { return }
            let animate = isAttached && !reduceMotion && count == lastCount + 1
            for (index, bead) in beads.enumerated() {
                place(bead, index: index, count: count, animated: animate)
            }
            lastCount = count
        }

        private func place(_ holder: Entity, index: Int, count: Int, animated: Bool) {
            let progress = Float(index + count % 33) / 33
            let point = Strand.point(at: progress)
            let tangent = Strand.point(at: progress + 0.002) - Strand.point(at: progress - 0.002)
            // Rotate only the stone; its small contact shadow stays on the display plane.
            if let stone = holder.children.first {
                stone.orientation = simd_quatf(angle: atan2(-tangent.x, tangent.y), axis: [0, 0, 1])
            }
            var transform = holder.transform
            transform.translation = point
            holder.stopAllAnimations()
            if animated {
                holder.move(to: transform, relativeTo: anchor, duration: 0.36, timingFunction: .easeInOut)
            } else {
                holder.transform = transform
            }
        }

        private func addImame() {
            let joint = Strand.point(at: 0)
            let ornament = Entity()
            ornament.name = "imame-and-tassel"
            ornament.position = joint + [0.004, -0.009, 0]
            ornament.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(SIMD3<Float>(0.76, -0.65, 0.06)))
            anchor.addChild(ornament)

            // Turned onyx spindle and understated warm metal ferrules.
            let profile: [(Float, Float)] = [
                (0, 0.0025), (0.003, 0.0041), (0.006, 0.0036), (0.010, 0.0032),
                (0.015, 0.0058), (0.022, 0.0071), (0.028, 0.0058),
                (0.034, 0.0038), (0.039, 0.0035), (0.041, 0.0044), (0.044, 0.0025)
            ]
            if let plain = SculptureGeometry.lathe(profile) {
                let wood = SculptureGeometry.lathe(profile, textured: true) ?? plain
                spindleMeshes = (plain, wood)
                let mesh = appearance.material == .wood ? wood : plain
                let body = ModelEntity(mesh: mesh, materials: [SculptureMaterials.bead(appearance, variation: 1, dark: isDark)])
                ornament.addChild(body)
                spindle = body
            }
            for y in [Float(0.005), 0.038, 0.041] {
                let collar = ModelEntity(mesh: SculptureGeometry.cylinder(height: 0.0014, radius: y < 0.01 ? 0.0041 : 0.0043),
                                         materials: [SculptureMaterials.brass])
                collar.position.y = y
                ornament.addChild(collar)
            }

            var threads: [([SIMD3<Float>], Float)] = []
            for index in 0..<15 {
                let spread = Float(index - 7) / 7
                let points = (0...8).map { step -> SIMD3<Float> in
                    let t = Float(step) / 8
                    return [spread * (0.001 + 0.009 * t) + sin(t * .pi) * 0.002,
                            0.044 + t * (0.040 + Float(index % 4) * 0.0015),
                            Float(index % 3 - 1) * 0.0006 + sin(t * .pi) * 0.001]
                }
                threads.append((points, 0.00032))
            }
            if let mesh = SculptureGeometry.tubes(threads) {
                let tassel = ModelEntity(mesh: mesh, materials: [SculptureMaterials.silk(dark: isDark)])
                ornament.addChild(tassel)
                cords.append(tassel)
            }
            let binding = ModelEntity(mesh: SculptureGeometry.cylinder(height: 0.004, radius: 0.0028),
                                      materials: [SculptureMaterials.silk(dark: isDark)])
            binding.position.y = 0.048
            ornament.addChild(binding)
            cords.append(binding)
        }
    }
}

/// Keep one renderer alive while SwiftUI changes the available width and height.
private final class SculptureARView: ARView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}

/// Keep the final lighting available before a new tab or Focus scene becomes visible.
@MainActor
private enum SculptureLighting {
    private(set) static var resource: EnvironmentResource?
    private static var loadingTask: Task<EnvironmentResource?, Never>?

    static func load() async -> EnvironmentResource? {
        if let resource { return resource }
        if let loadingTask { return await loadingTask.value }
        guard #available(iOS 18.0, *), let image = SculptureMaterials.studioImage() else { return nil }
        let task = Task { @MainActor in
            let environment = try? await EnvironmentResource(equirectangular: image, withName: "rosery-softbox")
            resource = environment
            loadingTask = nil
            return environment
        }
        loadingTask = task
        return await task.value
    }
}

/// Arc-length sampling gives each bead a physical amount of cord, even at the tighter bend.
private enum Strand {
    private static let samples: [SIMD3<Float>] = {
        let controls: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = [
            ([0.040, -0.111], [-0.050, -0.137], [-0.139, -0.041], [-0.100, 0.035]),
            ([-0.100, 0.035], [-0.071, 0.110], [-0.030, 0.138], [0.010, 0.118]),
            ([0.010, 0.118], [0.077, 0.116], [0.137, 0.068], [0.112, 0.020]),
            ([0.112, 0.020], [0.111, -0.049], [0.078, -0.112], [0.040, -0.111])
        ]
        return (0...720).map { index in
            let segment = min(index / 180, 3)
            let t = Float(index - segment * 180) / 180
            let q = 1 - t
            let (a, b, c, d) = controls[segment]
            let p = q * q * q * a + 3 * q * q * t * b + 3 * q * t * t * c + t * t * t * d
            let angle: Float = -0.42
            let stretched = SIMD2<Float>(p.x * 1.55, p.y * 0.58)
            let phase = Float(index) / 720 * 2 * .pi
            return [stretched.x * cos(angle) - stretched.y * sin(angle),
                    stretched.x * sin(angle) + stretched.y * cos(angle),
                    0.002 * sin(phase * 3) + 0.003 * cos(phase * 2)]
        }
    }()
    private static let lengths: [Float] = {
        var result: [Float] = [0]
        for index in 1..<samples.count { result.append(result[index - 1] + simd_distance(samples[index - 1], samples[index])) }
        return result
    }()

    static func point(at fraction: Float) -> SIMD3<Float> {
        let wrapped = fraction - floor(fraction)
        let distance = wrapped * (lengths.last ?? 1)
        let index = max(1, lengths.firstIndex(where: { $0 >= distance }) ?? 1)
        let t = (distance - lengths[index - 1]) / max(lengths[index] - lengths[index - 1], 0.00001)
        return simd_mix(samples[index - 1], samples[index], SIMD3(repeating: t))
    }
}

@MainActor
private enum SculptureMaterials {
    static func bead(_ appearance: BeadAppearance, variation: Int, dark: Bool) -> PhysicallyBasedMaterial {
        // Keep the original onyx finish unchanged, including its subtle per-bead variation.
        if appearance.material == .polished, appearance.color == .onyx {
            return onyx(variation: variation, dark: dark)
        }
        var material = PhysicallyBasedMaterial()
        var tint = palette(appearance.color, dark: dark)
        let variationFactor = 1 + Float(variation - 1) * 0.035
        switch appearance.material {
        case .polished:
            material.metallic = 0.18
            material.roughness = .init(floatLiteral: 0.20 + Float(variation) * 0.015)
            material.specular = 0.85
            material.clearcoat = 0.95
            material.clearcoatRoughness = 0.10
        case .matte:
            if appearance.color == .onyx { tint = dark ? [0.23, 0.235, 0.245] : [0.135, 0.138, 0.145] }
            material.metallic = 0.0
            material.roughness = 0.88
            material.specular = 0.22
            material.clearcoat = 0.0
        case .wood:
            if appearance.color == .onyx {
                tint = dark ? [0.32, 0.31, 0.29] : [0.23, 0.22, 0.20]
            } else {
                tint *= 1.20
            }
            material.metallic = 0.0
            material.roughness = 0.56
            material.specular = 0.30
            material.clearcoat = 0.12
            material.clearcoatRoughness = 0.48
        }
        tint = simd_clamp(tint * variationFactor, SIMD3(repeating: 0), SIMD3(repeating: 0.95))
        let color = UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1)
        if appearance.material == .wood, let texture = woodTextures[variation % woodTextures.count] {
            material.baseColor = .init(tint: color, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: color)
        }
        return material
    }

    private static func palette(_ color: BeadAppearance.Color, dark: Bool) -> SIMD3<Float> {
        switch color {
        case .onyx: dark ? [0.15, 0.153, 0.159] : [0.078, 0.07956, 0.08268]
        case .ivory: dark ? [0.78, 0.73, 0.63] : [0.70, 0.64, 0.53]
        case .amber: dark ? [0.58, 0.34, 0.14] : [0.44, 0.22, 0.07]
        case .olive: dark ? [0.35, 0.44, 0.25] : [0.24, 0.30, 0.16]
        case .rose: dark ? [0.59, 0.36, 0.40] : [0.46, 0.25, 0.29]
        case .ocean: dark ? [0.21, 0.40, 0.50] : [0.12, 0.29, 0.37]
        }
    }

    // Three deterministic grain maps are shared by every strand and every color. Generating
    // them lazily keeps the standard beads unchanged and avoids work during later updates.
    private static let woodTextures: [TextureResource?] = (0..<3).map { variation in
        let size = 256
        let phase = Double(variation) * 1.37
        let tau = Double.pi * 2
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            let v = Double(y) / Double(size)
            for x in 0..<size {
                let u = Double(x) / Double(size)
                let flow = u + 0.010 * sin(v * tau + phase) + 0.005 * sin(v * tau * 3 + phase * 2)
                let growth = 0.5 + 0.5 * sin(flow * tau * 11 + 0.35 * sin(v * tau))
                let pore = pow(0.5 + 0.5 * sin(flow * tau * 47), 18)
                let fineGrain = 0.012 * sin((u * 67 + v * 29) * tau + phase)
                let tone = min(1, max(0, 0.77 + 0.14 * growth - 0.055 * pore + fineGrain))
                let index = (y * size + x) * 4
                pixels[index] = UInt8(tone * 255)
                pixels[index + 1] = UInt8(tone * 250)
                pixels[index + 2] = UInt8(tone * 240)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    static func onyx(variation: Int, dark: Bool) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let value = CGFloat((dark ? 0.15 : 0.078) + Double(variation) * 0.008)
        material.baseColor = .init(tint: UIColor(red: value, green: value * 1.02, blue: value * 1.06, alpha: 1))
        material.metallic = 0.28
        material.roughness = .init(floatLiteral: 0.20 + Float(variation) * 0.015)
        material.specular = 0.85
        material.clearcoat = 0.95
        material.clearcoatRoughness = 0.10
        return material
    }

    static var brass: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.51, green: 0.39, blue: 0.22, alpha: 1))
        material.metallic = 0.9
        material.roughness = 0.28
        return material
    }

    static func silk(dark: Bool) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: dark ? 0.28 : 0.12, alpha: 1))
        material.roughness = 0.7
        return material
    }

    static func studioImage() -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format).image { renderer in
            let context = renderer.cgContext
            UIColor(white: 0.20, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            UIColor(white: 0.055, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 290, width: 1024, height: 222))
            context.setShadow(offset: .zero, blur: 18, color: UIColor.white.cgColor)
            UIColor(white: 1, alpha: 1).setFill()
            context.fill(CGRect(x: 165, y: 90, width: 165, height: 165))
            UIColor(white: 0.80, alpha: 1).setFill()
            context.fill(CGRect(x: 700, y: 80, width: 30, height: 225))
            UIColor(white: 0.60, alpha: 1).setFill()
            context.fill(CGRect(x: 920, y: 140, width: 55, height: 130))
        }.cgImage
    }

    static func shadow() -> UnlitMaterial? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { renderer in
            let colors = [UIColor.black.withAlphaComponent(0.24).cgColor, UIColor.clear.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            renderer.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 2,
                                                 endCenter: CGPoint(x: 32, y: 32), endRadius: 31, options: [])
        }
        return shadowMaterial(image)
    }

    static func combinedShadow() -> ModelEntity? {
        // A whole count only permutes the same 33 resting positions around the strand.
        let centers = (0..<33).map { Strand.point(at: Float($0) / 33) + SIMD3<Float>(0.0025, -0.004, 0) }
        let minX = (centers.map(\.x).min() ?? 0) - 0.018
        let maxX = (centers.map(\.x).max() ?? 0) + 0.018
        let minY = (centers.map(\.y).min() ?? 0) - 0.0165
        let maxY = (centers.map(\.y).max() ?? 0) + 0.0165
        let width = maxX - minX
        let height = maxY - minY
        let pixelsPerMeter = CGFloat(1024 / width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: CGFloat(height) * pixelsPerMeter), format: format).image { renderer in
            let context = renderer.cgContext
            let colors = [UIColor.black.withAlphaComponent(0.24).cgColor, UIColor.clear.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            for center in centers {
                context.saveGState()
                context.translateBy(x: CGFloat(center.x - minX) * pixelsPerMeter,
                                    y: CGFloat(maxY - center.y) * pixelsPerMeter)
                context.scaleBy(x: 0.018 * pixelsPerMeter, y: 0.0165 * pixelsPerMeter)
                context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 2 / 32,
                                           endCenter: .zero, endRadius: 31 / 32, options: [])
                context.restoreGState()
            }
        }
        guard let material = shadowMaterial(image) else { return nil }
        let shadow = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [material])
        shadow.name = "strand-contact-shadow"
        shadow.position = [(minX + maxX) / 2, (minY + maxY) / 2, -0.019]
        return shadow
    }

    private static func shadowMaterial(_ image: UIImage) -> UnlitMaterial? {
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: .black, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        if #available(iOS 18.0, *) {
            // Alpha-blended shadow quads must not write rectangular silhouettes into depth.
            // Keep depth testing so the opaque beads and cord still occlude their shadows.
            material.writesDepth = false
            material.readsDepth = true
        }
        return material
    }
}

@MainActor
private enum SculptureGeometry {
    private static let roundBead = MeshResource.generateSphere(radius: 0.0095)
    private static let facetedBead: MeshResource = {
        let t = Float((1 + sqrt(5.0)) / 2)
        let vertices: [SIMD3<Float>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]
        ].map { simd_normalize($0) }
        let faces = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
        ]
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var triangles: [UInt32] = []
        func addFace(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            let normal = simd_normalize(simd_cross(b - a, c - a))
            let points = [a, b, c]
            var uv = points.map { SIMD2<Float>(0.5 + atan2($0.z, $0.x) / (2 * .pi), acos($0.y) / .pi) }
            // Unwrap faces crossing the texture seam so grain stays narrow and continuous.
            if (uv.map(\.x).max() ?? 0) - (uv.map(\.x).min() ?? 0) > 0.5 {
                for index in uv.indices where uv[index].x < 0.5 { uv[index].x += 1 }
            }
            let start = UInt32(positions.count)
            positions.append(contentsOf: points.map { $0 * 0.0095 })
            normals.append(contentsOf: [normal, normal, normal])
            coordinates.append(contentsOf: uv)
            triangles.append(contentsOf: [start, start + 1, start + 2])
        }
        for face in faces {
            let a = vertices[face[0]], b = vertices[face[1]], c = vertices[face[2]]
            let ab = simd_normalize(a + b), bc = simd_normalize(b + c), ca = simd_normalize(c + a)
            addFace(a, ab, ca)
            addFace(b, bc, ab)
            addFace(c, ca, bc)
            addFace(ab, bc, ca)
        }
        return mesh(positions: positions, normals: normals, triangles: triangles, coordinates: coordinates) ?? roundBead
    }()

    static func bead(_ shape: BeadAppearance.Shape) -> MeshResource {
        shape == .faceted ? facetedBead : roundBead
    }

    static func beadScale(_ shape: BeadAppearance.Shape, index: Int) -> SIMD3<Float> {
        let width = Float(1) + Float(index % 4) * 0.009
        switch shape {
        case .oval: return [width, 1.10, 0.96]
        case .round: return SIMD3(repeating: width)
        case .faceted: return SIMD3(repeating: width * 1.025)
        }
    }

    static func cylinder(height: Float, radius: Float) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        let sides = 32
        for ring in 0..<sides {
            let angle = Float(ring) / Float(sides) * 2 * .pi
            let normal = SIMD3<Float>(cos(angle), 0, sin(angle))
            positions.append(normal * radius + [0, -height / 2, 0])
            positions.append(normal * radius + [0, height / 2, 0])
            normals.append(contentsOf: [normal, normal])
            let a = UInt32(ring * 2)
            let b = UInt32((ring + 1) % sides * 2)
            triangles.append(contentsOf: [a, a + 1, b, b, a + 1, b + 1])
        }
        for sign in [Float(-1), 1] {
            let center = UInt32(positions.count)
            positions.append([0, sign * height / 2, 0])
            normals.append([0, sign, 0])
            for ring in 0..<sides {
                let angle = Float(ring) / Float(sides) * 2 * .pi
                positions.append([radius * cos(angle), sign * height / 2, radius * sin(angle)])
                normals.append([0, sign, 0])
                let a = center + 1 + UInt32(ring)
                let b = center + 1 + UInt32((ring + 1) % sides)
                triangles.append(contentsOf: sign > 0 ? [center, b, a] : [center, a, b])
            }
        }
        return mesh(positions: positions, normals: normals, triangles: triangles) ?? .generateSphere(radius: radius)
    }

    static func tubes(_ strands: [([SIMD3<Float>], Float)]) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        let sides = 6
        for (points, radius) in strands {
            let base = positions.count
            for index in points.indices {
                let tangent = simd_normalize(points[min(index + 1, points.count - 1)] - points[max(index - 1, 0)])
                let side = simd_normalize(simd_cross(tangent, SIMD3<Float>(0, 0, 1)))
                let up = simd_cross(side, tangent)
                for ring in 0..<sides {
                    let angle = Float(ring) / Float(sides) * .pi * 2
                    let normal = side * cos(angle) + up * sin(angle)
                    positions.append(points[index] + normal * radius)
                    normals.append(normal)
                    if index < points.count - 1 {
                        let a = UInt32(base + index * sides + ring)
                        let b = UInt32(base + index * sides + (ring + 1) % sides)
                        let c = a + UInt32(sides)
                        let d = b + UInt32(sides)
                        triangles.append(contentsOf: [a, c, b, b, c, d])
                    }
                }
            }
        }
        return mesh(positions: positions, normals: normals, triangles: triangles)
    }

    static func lathe(_ profile: [(Float, Float)], textured: Bool = false) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var triangles: [UInt32] = []
        let sides = 32
        // The textured spindle duplicates its seam vertex; the original plain mesh stays exact.
        let stride = sides + (textured ? 1 : 0)
        for index in profile.indices {
            let (height, radius) = profile[index]
            let before = profile[max(0, index - 1)]
            let after = profile[min(profile.count - 1, index + 1)]
            let slope = (after.1 - before.1) / max(after.0 - before.0, 0.0001)
            for ring in 0..<stride {
                let angle = Float(ring) / Float(sides) * 2 * .pi
                positions.append([radius * cos(angle), height, radius * sin(angle)])
                normals.append(simd_normalize([cos(angle), -slope, sin(angle)]))
                coordinates.append([Float(ring) / Float(sides), height / max(profile.last?.0 ?? 1, 0.0001)])
                if index < profile.count - 1, ring < sides {
                    let a = UInt32(index * stride + ring)
                    let next = textured ? ring + 1 : (ring + 1) % sides
                    let b = UInt32(index * stride + next)
                    triangles.append(contentsOf: [a, a + UInt32(stride), b, b, a + UInt32(stride), b + UInt32(stride)])
                }
            }
        }
        return mesh(positions: positions, normals: normals, triangles: triangles, coordinates: textured ? coordinates : nil)
    }

    private static func mesh(positions: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [UInt32],
                             coordinates: [SIMD2<Float>]? = nil) -> MeshResource? {
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        if let coordinates { descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates) }
        descriptor.primitives = .triangles(triangles)
        return try? MeshResource.generate(from: [descriptor])
    }
}

struct CounterSurface: View {
    @Environment(RoseryStore.self) private var store
    var large = false

    var body: some View {
        Button { CountInteraction.increment(store) } label: {
            BeadRing(count: store.progress.count, target: store.progress.target, wide: !large,
                     appearance: store.beadAppearance)
                .contentShape(.rect)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CounterButtonStyle())
        .disabled(store.progress.isComplete)
        .accessibilityLabel("Count \(store.selectedDhikr.title)")
        .accessibilityValue("\(store.progress.count) of \(store.progress.target)\(store.isPersonalTarget ? ", personal target" : "")\(store.progress.isComplete ? ", complete" : "")")
        .accessibilityHint("Adds one remembrance")
        .accessibilityIdentifier("tasbih.counter")
    }
}
