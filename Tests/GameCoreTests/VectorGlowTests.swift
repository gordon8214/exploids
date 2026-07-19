import XCTest
import SpriteKit
import Metal
@testable import GameCore

@MainActor
final class VectorGlowTests: GameCoreTestCase {
    private let renderSize = 64

    func testHDRStrokeProducesValuesAboveSDRWithinTargetHeadroom() throws {
        resetRenderer()
        let shape = makeTestShape()
        VectorGlowRenderer.markStroke(shape)

        let pixels = try render(shape, active: true, headroom: 3.0)
        let brightest = maximumRGB(in: pixels)

        XCTAssertGreaterThan(brightest, 1.0)
        XCTAssertLessThanOrEqual(brightest, 3.05)
        XCTAssertEqual(shape.lineWidth, 2.0)
        XCTAssertEqual(shape.glowWidth, 0.0)
        XCTAssertNotNil(shape.strokeShader)
        XCTAssertNil(shape.fillShader)
    }

    func testClassicAsteroidOutlineStillProducesEDRValuesAboveWhite() throws {
        resetRenderer()
        let asteroid = Asteroid(sizeClass: .large)
        asteroid.applyClassicAppearance(family: 2)
        asteroid.setScale(0.55)

        let pixels = try render(asteroid, active: true, headroom: 2.4)
        XCTAssertGreaterThan(maximumRGB(in: pixels), 1.0)
        XCTAssertEqual(asteroid.fillColor.alphaComponent, 0.0)
        XCTAssertTrue(VectorGlowRenderer.isStrokeMarked(asteroid))
    }

    func testInactiveMarkedShapeMatchesUnmarkedSDRRendering() throws {
        resetRenderer()
        let baseline = makeTestShape()
        let baselinePixels = try render(baseline, active: false, headroom: 1.0)

        let marked = makeTestShape()
        VectorGlowRenderer.markStroke(marked)
        let markedPixels = try render(marked, active: false, headroom: 3.0)

        XCTAssertEqual(markedPixels, baselinePixels)
        XCTAssertEqual(marked.glowWidth, 0.0)
        XCTAssertNil(marked.strokeShader)
        XCTAssertNil(marked.fillShader)
    }

    func testStrokeGlowDoesNotBoostTranslucentInteriorFill() throws {
        resetRenderer()
        let shape = makeTestShape()
        VectorGlowRenderer.markStroke(shape)

        let pixels = try render(shape, active: true, headroom: 3.0)
        let center = rgb(in: pixels, x: renderSize / 2, y: renderSize / 2)

        XCTAssertGreaterThan(maximumRGB(in: pixels), 1.0)
        XCTAssertLessThanOrEqual(center.max() ?? 0.0, 1.0)
        XCTAssertNil(shape.fillShader)
    }

    func testGameplayVectorFamiliesAreMarkedWithoutMarkingTextOrRasterArt() {
        resetRenderer()
        let ship = Ship()
        XCTAssertTrue(VectorGlowRenderer.isStrokeMarked(ship))
        XCTAssertGreaterThanOrEqual(markedStrokeShapes(in: ship).count, 5)

        let asteroid = Asteroid(sizeClass: .large)
        XCTAssertTrue(VectorGlowRenderer.isStrokeMarked(asteroid))
        XCTAssertGreaterThanOrEqual(markedStrokeShapes(in: asteroid).count, 2)

        let ufo = UFO(isSmall: false, startOnLeft: true, screenSize: CGSize(width: 800, height: 600))
        let laser = Laser(position: .zero, angle: 0.0)
        let powerUp = PowerUp(type: .shield, position: .zero)
        let gravityWell = GravityWell()
        let option = OptionDrone()
        for shape in [ufo, laser, powerUp, gravityWell, option] {
            XCTAssertTrue(VectorGlowRenderer.isStrokeMarked(shape))
        }
        XCTAssertGreaterThanOrEqual(markedStrokeShapes(in: gravityWell).count, 2)

        let powerUpLabel = powerUp.children.compactMap { $0 as? SKLabelNode }.first
        XCTAssertNotNil(powerUpLabel)

        let head = FloatingHead(screenSize: CGSize(width: 800, height: 600))
        XCTAssertFalse(descendants(of: head, as: SKSpriteNode.self).isEmpty)
        XCTAssertFalse(markedStrokeShapes(in: head).isEmpty)
        XCTAssertFalse(markedFillShapes(in: head).isEmpty)
    }

    private func makeTestShape() -> SKShapeNode {
        let shape = SKShapeNode(rectOf: CGSize(width: 24, height: 24))
        shape.strokeColor = .white
        shape.fillColor = SKColor(white: 1.0, alpha: 0.2)
        shape.lineWidth = 2.0
        return shape
    }

    private func resetRenderer() {
        VectorGlowRenderer.update(in: SKNode(), active: false, headroom: 1.0)
    }

    private func render(_ shape: SKShapeNode, active: Bool, headroom: CGFloat) throws -> [Float16] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw XCTSkip("Metal ist auf diesem Testsystem nicht verfügbar.")
        }

        let scene = SKScene(size: CGSize(width: renderSize, height: renderSize))
        scene.backgroundColor = .black
        shape.position = CGPoint(x: renderSize / 2, y: renderSize / 2)
        scene.addChild(shape)
        VectorGlowRenderer.update(in: scene, active: active, headroom: headroom)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: renderSize,
            height: renderSize,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            XCTFail("RGBA16Float-Testtextur konnte nicht erzeugt werden.")
            return []
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        renderer.update(atTime: 0.0)
        renderer.render(
            withViewport: CGRect(x: 0, y: 0, width: renderSize, height: renderSize),
            commandBuffer: commandBuffer,
            renderPassDescriptor: pass
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [Float16](repeating: 0, count: renderSize * renderSize * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: renderSize * 4 * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, renderSize, renderSize),
            mipmapLevel: 0
        )
        return pixels
    }

    private func maximumRGB(in pixels: [Float16]) -> Float {
        stride(from: 0, to: pixels.count, by: 4).reduce(0.0) { result, index in
            max(result, Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]))
        }
    }

    private func rgb(in pixels: [Float16], x: Int, y: Int) -> [Float] {
        let index = (y * renderSize + x) * 4
        return [Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2])]
    }

    private func markedStrokeShapes(in root: SKNode) -> [SKShapeNode] {
        descendants(of: root, as: SKShapeNode.self).filter(VectorGlowRenderer.isStrokeMarked)
    }

    private func markedFillShapes(in root: SKNode) -> [SKShapeNode] {
        descendants(of: root, as: SKShapeNode.self).filter(VectorGlowRenderer.isFillMarked)
    }

    private func descendants<T: SKNode>(of root: SKNode, as type: T.Type) -> [T] {
        var result: [T] = []
        if let match = root as? T { result.append(match) }
        for child in root.children {
            result.append(contentsOf: descendants(of: child, as: type))
        }
        return result
    }
}
