import Foundation
import SpriteKit
import Metal
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import GameCore

/// Headless-Renderer: erzeugt aus einer `Replay`-Aufnahme deterministisch eine animierte GIF-Datei –
/// ganz ohne sichtbares Fenster (passt zur Headless-/Agent-Linie des Projekts). Genutzt vom
/// CLI-Flag `--render-replay` (siehe Main.swift).
///
/// Ablauf je Schritt: `scene.advanceOneStep()` treibt genau einen festen Simulationsschritt voran
/// (speist die aufgezeichneten Eingaben ein), `SKRenderer.update(atTime:)` tickt die visuellen
/// SKActions auf dieselbe Sim-Zeit, und `SKRenderer.render(...)` zeichnet den Zustand in eine
/// Offscreen-Metal-Textur, die als `CGImage` gelesen und per ImageIO zu einem GIF kodiert wird.
/// `@MainActor`, weil die Render-Funktionen eine `GameScene` treiben und SpriteKit ansteuern (alles
/// MainActor). Läuft im CLI-Pfad ohnehin auf dem Main-Thread; unter Swift 6.1 sind die Aufrufe ohne
/// die Annotation Fehler (nicht bloß Warnungen wie auf neueren Toolchains).
@MainActor
enum ReplayRenderer {

    /// Render-Optionen mit vernünftigen Defaults für ein Promo-GIF.
    struct Options {
        /// Auflösung des GIFs (Ausgabe). Default kompakt für ein Web-GIF.
        var width: Int = 480
        var height: Int = 360
        /// Simulationsgröße (Szenengröße). MUSS der Aufnahme entsprechen, sonst driftet der Lauf
        /// (Spawns/Wrap/Bounds hängen an `size`). `nil` = wie Ausgabegröße. Für Aufnahmen aus dem
        /// macOS-Fenster (Default 1024×768) hier 1024×768 setzen; die Ausgabe wird beim Rendern skaliert.
        var simWidth: Int? = nil
        var simHeight: Int? = nil
        /// Nur jeden N-ten Simulationsschritt ins GIF aufnehmen. `nil` = automatisch so wählen, dass
        /// das GIF in Echtzeit läuft (Sim-Rate / fps, z. B. 120/30 → jeder 4.). Explizit setzen, um
        /// Zeitlupe/Zeitraffer zu erzwingen.
        var frameStride: Int? = nil
        /// Bilder pro Sekunde im GIF (Abspieltempo). 30 wirkt flüssig.
        var fps: Int = 30
        /// HUD/Overlay (Score, Timer, „REPLAY") ausblenden für ein sauberes Promo-GIF.
        var hideHUD: Bool = true
        /// Maximale Anzahl gerenderter Frames (Sicherheitsdeckel gegen riesige GIFs). 0 = unbegrenzt.
        var maxFrames: Int = 900
        /// Erst ab diesem Simulationsframe rendern (vorherige Frames werden nur simuliert, nicht
        /// aufgenommen). Damit lässt sich ein Ausschnitt aus der Mitte/dem Ende eines langen Laufs greifen.
        var startFrame: Int = 0
        /// Auto-Feuer-Zustand erzwingen (für alte Aufnahmen ohne gespeichertes Feld). `nil` = den
        /// in der Aufnahme gespeicherten Wert nutzen.
        var autoFireOverride: Bool? = nil
    }

    enum RenderError: Error, CustomStringConvertible {
        case noMetalDevice
        case textureCreationFailed
        case gifDestinationFailed
        case videoWriterFailed
        case noFramesRendered

        var description: String {
            switch self {
            case .noMetalDevice: return "Kein Metal-Gerät verfügbar (Offscreen-Rendering nicht möglich)."
            case .textureCreationFailed: return "Offscreen-Textur konnte nicht erstellt werden."
            case .gifDestinationFailed: return "GIF-Ziel konnte nicht erstellt werden."
            case .videoWriterFailed: return "Video-Writer konnte nicht erstellt/gestartet werden."
            case .noFramesRendered: return "Es wurden keine Frames gerendert (leere Aufnahme?)."
            }
        }
    }

    /// Rendert die Aufnahme in eine GIF-Datei.
    static func renderToGIF(_ replay: Replay, outputURL: URL, options: Options = Options()) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        guard let commandQueue = device.makeCommandQueue() else { throw RenderError.noMetalDevice }

        let width = options.width
        let height = options.height

        // Szene in SIMULATIONSGRÖSSE aufsetzen — per Default die in der Aufnahme gespeicherte Größe
        // (sonst driftet der Lauf); gerendert wird in die Ausgabe-Textur (width×height), SpriteKit
        // skaliert via scaleMode .fill. `--sim-scale` kann die Größe überschreiben.
        let simW = options.simWidth ?? replay.width
        let simH = options.simHeight ?? replay.height
        let scene = GameScene(size: CGSize(width: simW, height: simH))
        scene.scaleMode = .fill
        // Exportziele sind bewusst SDR (GIF/BGRA8 bzw. normales Video): keine Werte oberhalb von 1.
        scene.updateHDRDisplay(available: false, currentHeadroom: 1.0)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: simW, height: simH))
        view.presentScene(scene)
        if options.hideHUD { scene.setHUDHiddenForRender(true) }
        scene.replayAutoFireOverride = options.autoFireOverride
        guard scene.startReplay(replay) else { throw RenderError.noFramesRendered }

        // Offscreen-Renderer + Ziel-Textur (Apple Silicon: .shared erlaubt direktes getBytes).
        let renderer = SKRenderer(device: device)
        renderer.scene = scene

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else {
            throw RenderError.textureCreationFailed
        }

        let viewport = CGRect(x: 0, y: 0, width: width, height: height)
        var images: [CGImage] = []

        // Simulation hier explizit Schritt für Schritt treiben (advanceOneStep); der normale
        // Echtzeit-Akkumulator in update(_:) bleibt damit außen vor. `renderer.update(atTime:)` tickt
        // nur noch die visuellen SKActions auf dieselbe Sim-Zeit. Je `stride` ein Bild aufnehmen.
        scene.externalStepDriving = true
        let stride = max(1, options.frameStride ?? (GameScene.simStepsPerSecond / max(1, options.fps)))
        var simFrame = 0
        var simTime: TimeInterval = 0.0
        while scene.advanceOneStep() {            // ein fester Sim-Schritt; false = Aufnahme zu Ende
            simTime += GameScene.simStep
            renderer.update(atTime: simTime)       // SKActions/visuelle Effekte auf simTime ticken

            // Schritte vor dem gewünschten Startpunkt nur simulieren, nicht aufnehmen (Ausschnitt-Wahl).
            if simFrame < options.startFrame {
                simFrame += 1
                continue
            }

            if (simFrame - options.startFrame) % stride == 0 {
                // Asteroiden-Drahtgitter vor dem Capture neu aufbauen (der Sim-Schritt tut das nicht
                // mehr pro Schritt, sondern der Host pro gerendertem Bild — hier headless).
                scene.refreshAsteroidWireframes()
                if let img = renderFrame(renderer: renderer, commandQueue: commandQueue,
                                         texture: texture, viewport: viewport) {
                    images.append(img)
                }
                if options.maxFrames > 0 && images.count >= options.maxFrames { break }
            }
            simFrame += 1
        }

        guard !images.isEmpty else { throw RenderError.noFramesRendered }
        try encodeGIF(images: images, fps: options.fps, to: outputURL)
    }

    /// Rendert die Aufnahme als h264-Video (mp4). Für lange Läufe gedacht, die als GIF zu groß wären –
    /// in Echtzeit (Video-Zeit = Spielzeit), zum Durchscrubben und Auswählen eines GIF-Ausschnitts.
    /// Gleiche treue Simulation wie der GIF-Pfad (Sim in Aufnahme-Größe), Frames gehen aber über einen
    /// `AVAssetWriter` statt ImageIO.
    static func renderToVideo(_ replay: Replay, outputURL: URL, options: Options = Options()) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        guard let commandQueue = device.makeCommandQueue() else { throw RenderError.noMetalDevice }

        let width = options.width
        let height = options.height
        let simW = options.simWidth ?? replay.width
        let simH = options.simHeight ?? replay.height
        let scene = GameScene(size: CGSize(width: simW, height: simH))
        scene.scaleMode = .fill
        scene.updateHDRDisplay(available: false, currentHeadroom: 1.0)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: simW, height: simH))
        view.presentScene(scene)
        if options.hideHUD { scene.setHUDHiddenForRender(true) }
        scene.replayAutoFireOverride = options.autoFireOverride
        guard scene.startReplay(replay) else { throw RenderError.noFramesRendered }

        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else {
            throw RenderError.textureCreationFailed
        }
        let viewport = CGRect(x: 0, y: 0, width: width, height: height)

        // AVAssetWriter (h264/mp4) – ohne Fenster, rein dateibasiert (passt zur Headless-Linie).
        try? FileManager.default.removeItem(at: outputURL)
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw RenderError.videoWriterFailed
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])
        guard writer.canAdd(input) else { throw RenderError.videoWriterFailed }
        writer.add(input)
        guard writer.startWriting() else { throw RenderError.videoWriterFailed }
        writer.startSession(atSourceTime: .zero)

        let fps = max(1, options.fps)
        let stride = max(1, options.frameStride ?? (GameScene.simStepsPerSecond / fps))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        var videoFrame = 0
        var simFrame = 0
        var simTime: TimeInterval = 0.0
        scene.externalStepDriving = true
        while scene.advanceOneStep() {
            simTime += GameScene.simStep
            renderer.update(atTime: simTime)
            if simFrame < options.startFrame { simFrame += 1; continue }
            if (simFrame - options.startFrame) % stride == 0 {
                // Asteroiden-Drahtgitter vor dem Capture neu aufbauen (siehe GIF-Pfad oben).
                scene.refreshAsteroidWireframes()
                if let img = renderFrame(renderer: renderer, commandQueue: commandQueue,
                                         texture: texture, viewport: viewport),
                   let buf = makePixelBuffer(from: img, width: width, height: height) {
                    while !input.isReadyForMoreMediaData { usleep(500) }
                    adaptor.append(buf, withPresentationTime:
                        CMTimeMultiply(frameDuration, multiplier: Int32(videoFrame)))
                    videoFrame += 1
                }
                if options.maxFrames > 0 && videoFrame >= options.maxFrames { break }
            }
            simFrame += 1
        }

        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        guard videoFrame > 0, writer.status == .completed else { throw RenderError.videoWriterFailed }
    }

    /// Zeichnet ein `CGImage` in einen frischen BGRA-`CVPixelBuffer` für den Video-Writer.
    private static func makePixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// Rendert den aktuellen Szenenzustand in die Textur und liest ihn als `CGImage` zurück.
    private static func renderFrame(renderer: SKRenderer, commandQueue: MTLCommandQueue,
                                    texture: MTLTexture, viewport: CGRect) -> CGImage? {
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }
        renderer.render(withViewport: viewport, commandBuffer: cmdBuf, renderPassDescriptor: passDesc)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return cgImage(from: texture)
    }

    /// Liest eine BGRA8-`.shared`-Textur in ein `CGImage` (Y nicht gespiegelt – SpriteKit rendert
    /// bereits in Bildschirm-Orientierung).
    private static func cgImage(from texture: MTLTexture) -> CGImage? {
        let w = texture.width, h = texture.height
        let rowBytes = w * 4
        var data = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(&data, bytesPerRow: rowBytes,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // BGRA8 = byteOrder32Little + premultipliedFirst (Alpha vorne).
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: rowBytes, space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else { return nil }
        return ctx.makeImage()
    }

    /// Kodiert die Frames als animiertes GIF (Endlosschleife) per ImageIO.
    private static func encodeGIF(images: [CGImage], fps: Int, to url: URL) throws {
        let gifType = UTType.gif.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, gifType, images.count, nil) else {
            throw RenderError.gifDestinationFailed
        }
        let fileProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFLoopCount as String: 0]]    // 0 = Endlosschleife
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let delay = 1.0 / Double(max(1, fps))
        let frameProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFDelayTime as String: delay]]
        for img in images {
            CGImageDestinationAddImage(dest, img, frameProps as CFDictionary)
        }
        if !CGImageDestinationFinalize(dest) {
            throw RenderError.gifDestinationFailed
        }
    }
}
