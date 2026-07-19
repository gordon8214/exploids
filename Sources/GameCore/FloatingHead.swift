import SpriteKit

/// Der Kopf-Boss „Der Götze" – ein geschnitzter Greisen-Totem als echter Boss (kein normaler
/// Gegner). Er ist ein **reiner Spawner**: Er schwebt herein, lauert eine Weile (Augen folgen dem
/// Schiff), öffnet dann den Mund und speit eine **Armada von 10 UFOs** (Mix aus großen und kleinen)
/// gestaffelt aus dem Mund-Mittelpunkt, und zieht sich danach zurück.
///
/// Strategie für den Spieler: den Kopf möglichst **vor** dem Mund-Öffnen mit 3 Treffern zerstören,
/// sonst wenigstens die UFOs beim Herauskommen abfangen. Wird der Kopf **während** des Ausstoßes
/// zerstört, bleiben die restlichen UFOs aus (das erledigt die GameScene, indem sie den Kopf entfernt).
///
/// Aussehen wird in den **Koordinaten des Design-Mockups** aufgebaut (y nach unten). Damit der Kopf
/// in SpriteKit (y nach oben) aufrecht steht, sitzen alle Grafikteile in einem Container `art`, der
/// per `yScale < 0` gespiegelt ist; ein Skalierungsfaktor bringt ihn auf die gewünschte Spielgröße.
public final class FloatingHead: SKNode {

    /// Die Phasen des Boss-Lebenszyklus.
    public enum Phase: Sendable, Equatable {
        case entering    // schwebt vom oberen Rand herein
        case lurking     // lauert, Augen tracken – Zeitfenster zum Töten
        case spawning    // Mund auf, speit die UFO-Armada
        case retreating  // Mund zu, zieht sich zurück
    }

    // MARK: - Zustand

    public private(set) var phase: Phase = .entering
    /// Treffer bis zur Zerstörung – zentral justierbar (Boss). Playtest mit 10, evtl. später 20.
    public static var hitsToDestroy: Int = 10
    /// Verbleibende Treffer bis zur Zerstörung.
    public private(set) var hitsRemaining: Int = FloatingHead.hitsToDestroy
    private let maxHits: Int = FloatingHead.hitsToDestroy
    /// True, sobald der Kopf sich nach dem Rückzug komplett aus dem Bild entfernt hat.
    public private(set) var isFinished: Bool = false

    /// Ungefährer Kollisionsradius (Kreis) in Szenen-Einheiten – etwas größer als der größte
    /// Asteroid (Radius 40).
    public let collisionRadius: CGFloat = 68.0

    /// Zeitpunkt des letzten Laserbeam-Treffers (Treffer-Drosselung des Dauer-Strahls, damit der
    /// Boss nicht in Sekundenbruchteilen zerschmilzt). Wird von der GameScene gesetzt.
    public var lastBeamHitTime: TimeInterval = 0.0

    /// Aktueller Mund-Öffnungsgrad (0 = zu, 1 = ganz offen) – steuert u.a. die Boss-Stimme.
    public var mouthOpenness: CGFloat { mouthProgress }

    // MARK: - Tuning (für Tests überschreibbar)

    /// Lauer-Dauer in Sekunden, bis der Mund aufgeht (im Spiel zufällig ~3–5 s, ø 4). Wird im
    /// deterministischen Initializer aus dem `rng` gesetzt; der Literal-Default 4.0 dient nur als
    /// Platzhalter (z. B. für den Archivierungs-Pfad) und wird von Tests ohnehin überschrieben.
    public var lurkDuration: TimeInterval = 4.0
    /// Dauer des Mund-Öffnens bzw. -Schließens.
    public var mouthMoveDuration: TimeInterval = 0.45
    /// Abstand zwischen zwei ausgespienen UFOs.
    public var spawnInterval: TimeInterval = 0.25
    /// Gesamtzahl auszuspeiender UFOs.
    public var totalSpawns: Int = 10

    // MARK: - Intern

    private let screenSize: CGSize
    private let hoverTarget: CGPoint
    private let offscreenY: CGFloat
    private let enterSpeed: CGFloat = 190.0

    private var stateTime: TimeInterval = 0.0
    private var spawnsDone: Int = 0
    private var spawnAccumulator: TimeInterval = 0.0

    // Aktive Ausweich-Bewegung (Steering): der Kopf flieht vor dem Schiff und weicht den Schüssen
    // des Spielers aus – zügig, aber gedeckelt. Gleicht aus, dass er groß und 10 Treffer braucht.
    private var moveVelocity: CGPoint = .zero
    private let maxMoveSpeed: CGFloat = 300.0     // „zügig", nicht Wahnsinn
    private let fleeStrength: CGFloat = 360.0     // Beschleunigung weg vom Schiff
    private let fleeRange: CGFloat = 380.0        // ab hier wird das Fliehen spürbar stärker
    private let dodgeStrength: CGFloat = 1000.0   // Ausweichen vor Schüssen
    private let dodgeRadius: CGFloat = 95.0       // seitlicher Gefahren-Korridor um einen Schuss
    private let dodgeLookahead: CGFloat = 280.0   // wie weit voraus Schüsse beachtet werden
    private let boundsStrength: CGFloat = 26.0    // hält ihn im sichtbaren Bereich
    private let moveFriction: CGFloat = 0.86      // Dämpfung (pro 1/60 s), frameraten-normiert
    /// 0 = Mund zu, 1 = Mund ganz offen.
    private var mouthProgress: CGFloat = 0.0

    // Darstellung: vektorisierte Kontur als Textur (Art/zardoz_head.png, Silber auf transparent –
    // der Zardoz-„Schrei"-Patch). `headHeight` ist die Bildhöhe in Szenen-Einheiten; Augen/Mund als
    // normierte Texturkoordinaten (0..1, y nach unten), zentral justierbar. Aus ihnen werden die
    // Pupillen-Sockel (bewegliche Augen) und der Mund-Mittelpunkt (UFO-Spawn) berechnet. Der Schrei-
    // Mund ist dauerhaft offen – es gibt keine sichtbare Mund-Animation mehr.
    private let headHeight: CGFloat = 220.0
    private let leftEyeNorm  = CGPoint(x: 0.264, y: 0.31)
    private let rightEyeNorm = CGPoint(x: 0.514, y: 0.31)
    private let mouthNorm    = CGPoint(x: 0.386, y: 0.52)

    // Grafik-Referenzen
    private let art = SKNode()
    private var headSprite: SKSpriteNode!
    private var leftPupil: SKShapeNode!
    private var rightPupil: SKShapeNode!
    private var leftSocketCenter: CGPoint = .zero    // lokale Augen-Mitten (in buildArt berechnet)
    private var rightSocketCenter: CGPoint = .zero
    private var mouthLocal: CGPoint = .zero          // lokaler Mund-Mittelpunkt (UFO-Spawn-Ursprung)
    // Schadens-Risse (anfangs versteckt, je Treffer eine Stufe sichtbar).
    private var leftEyeCrack: SKShapeNode!
    private var rightEyeCrack: SKShapeNode!
    private var jawCrack: SKShapeNode!

    // Farben (Glüh-Augen + Risse; Stein nur noch als Fallback-Kontur ohne Textur).
    private let eyeGlow = SKColor(red: 0.92, green: 1.0,  blue: 0.97, alpha: 1.0)
    private let pupilCol = SKColor(red: 1.0,  green: 0.27, blue: 0.14, alpha: 1.0)
    private let crackRed = SKColor(red: 1.0, green: 0.23, blue: 0.42, alpha: 1.0)
    private let stone   = SKColor(red: 0.79, green: 0.71, blue: 0.53, alpha: 1.0)

    // MARK: - Init

    /// Erzeugt den Kopf-Boss für eine gegebene Szenengröße. Er startet über dem oberen Bildrand und
    /// schwebt in den oberen Bildbereich hinein.
    public init(screenSize: CGSize, using rng: inout GameRandom) {
        self.screenSize = screenSize
        self.hoverTarget = CGPoint(x: 0, y: screenSize.height * 0.18)
        self.offscreenY = screenSize.height * 0.5 + 280.0
        super.init()

        // Lauer-Dauer deterministisch aus dem geteilten rng (statt globalem System-RNG).
        self.lurkDuration = Double.random(in: 3.0...5.0, using: &rng)

        // Container aufrecht (die Textur ist bereits korrekt orientiert; keine Mockup-Spiegelung mehr).
        addChild(art)
        buildArt()

        self.position = CGPoint(x: 0, y: offscreenY)
        self.zPosition = 5
    }

    /// Convenience-Initializer ohne Seed für Tests/Helfer — würfelt aus dem System-RNG.
    /// NICHT im deterministischen Gameplay-Pfad verwenden (dafür den Initializer mit `using rng:`).
    public convenience init(screenSize: CGSize) {
        var throwaway = GameRandom(seed: GameRandom.systemSeed())
        self.init(screenSize: screenSize, using: &throwaway)
    }

    public required init?(coder aDecoder: NSCoder) {
        self.screenSize = CGSize(width: 1024, height: 768)
        self.hoverTarget = CGPoint(x: 0, y: 138)
        self.offscreenY = 664
        super.init(coder: aDecoder)
    }

    // MARK: - Öffentliche API (Spiel-Logik)

    /// Schreitet den Zustandsautomaten um `deltaTime` voran und richtet die Augen auf das Schiff aus.
    /// Rückgabewert: Anzahl der **in diesem Frame** auszuspeienden UFOs (0, außer in der Spawn-Phase).
    /// Die GameScene erzeugt diese UFOs dann an `mouthWorldPosition`.
    @discardableResult
    public func update(deltaTime: TimeInterval, shipPosition: CGPoint,
                       laserThreats: [(position: CGPoint, velocity: CGPoint)] = []) -> Int {
        trackEyes(towards: shipPosition)
        var emit = 0

        switch phase {
        case .entering:
            moveToward(hoverTarget, speed: enterSpeed, dt: deltaTime)
            if position.distance(to: hoverTarget) < 6.0 {
                position = hoverTarget
                phase = .lurking
                stateTime = 0.0
            }

        case .lurking:
            updateMovement(dt: deltaTime, shipPos: shipPosition, threats: laserThreats)
            stateTime += deltaTime
            if stateTime >= lurkDuration {
                phase = .spawning
                stateTime = 0.0
                spawnsDone = 0
                spawnAccumulator = 0.0
            }

        case .spawning:
            updateMovement(dt: deltaTime, shipPos: shipPosition, threats: laserThreats)
            // Mund öffnen.
            advanceMouth(toward: 1.0, dt: deltaTime)
            // Erst speien, wenn der Mund weit genug offen ist.
            if mouthProgress > 0.85 {
                spawnAccumulator += deltaTime
                while spawnAccumulator >= spawnInterval && spawnsDone < totalSpawns {
                    spawnAccumulator -= spawnInterval
                    spawnsDone += 1
                    emit += 1
                }
            }
            if emit > 0 { showMouthSpawnFlash() }
            if spawnsDone >= totalSpawns {
                phase = .retreating
                stateTime = 0.0
            }

        case .retreating:
            advanceMouth(toward: 0.0, dt: deltaTime)
            // Nach oben zurückziehen, von wo er kam.
            moveToward(CGPoint(x: position.x, y: offscreenY), speed: enterSpeed, dt: deltaTime)
            if position.y >= offscreenY - 1.0 {
                isFinished = true
            }
        }

        return emit
    }

    /// Verarbeitet einen Spieler-Treffer. Gibt `true` zurück, wenn der Kopf dadurch zerstört ist.
    /// Bei jedem Treffer ein sichtbares Feedback (Weiß-Flash + zunehmender Vektor-Schaden).
    @discardableResult
    public func registerHit() -> Bool {
        guard hitsRemaining > 0 else { return true }
        hitsRemaining -= 1
        showHitFeedback()
        updateDamageVisual()
        return hitsRemaining <= 0
    }

    /// Für Tests: versetzt den Kopf sofort in die Spawn-Phase an der Lauer-Position (offener Mund),
    /// damit die Einschweb-Phase nicht abgewartet werden muss.
    public func beginSpawningForTesting() {
        position = hoverTarget
        phase = .spawning
        stateTime = 0.0
        spawnsDone = 0
        spawnAccumulator = 0.0
        mouthProgress = 1.0
    }

    /// Weltkoordinaten des Mund-Mittelpunkts – Ursprung, an dem die UFOs materialisieren.
    public var mouthWorldPosition: CGPoint {
        if let scene = scene {
            return art.convert(mouthLocal, to: scene)
        }
        // Fallback ohne Szene (Tests): `art` ist aufrecht und unverschoben -> direkter Offset.
        return CGPoint(x: position.x + mouthLocal.x, y: position.y + mouthLocal.y)
    }

    // MARK: - Bewegung / Helfer
    // (`moveToward`/`distance` liegen zentral in VectorMath.swift — waren hier und in
    // SpaceCat identisch dupliziert.)

    /// Aktive Ausweich-Bewegung: flieht vor dem Schiff, weicht Spieler-Schüssen aus und bleibt im
    /// sichtbaren Bereich. Bewusst gedeckelt („zügig, nicht Wahnsinn"). Funktioniert in beiden Modi
    /// gleich (kein zusätzliches Mad-Mitrotieren → kein Schwindel).
    private func updateMovement(dt: TimeInterval, shipPos: CGPoint,
                                threats: [(position: CGPoint, velocity: CGPoint)]) {
        var fx: CGFloat = 0, fy: CGFloat = 0

        // 1. Vor dem Schiff fliehen (stärker, je näher).
        let ax = position.x - shipPos.x, ay = position.y - shipPos.y
        let d = max(1.0, hypot(ax, ay))
        let fleeMag = fleeStrength * min(1.6, fleeRange / d)
        fx += ax / d * fleeMag
        fy += ay / d * fleeMag

        // 2. Spieler-Schüssen ausweichen (seitlich aus der Schussbahn gleiten).
        for t in threats {
            let dirLen = hypot(t.velocity.x, t.velocity.y)
            guard dirLen > 0.001 else { continue }
            let dx = t.velocity.x / dirLen, dy = t.velocity.y / dirLen
            let tx = position.x - t.position.x, ty = position.y - t.position.y
            let along = tx * dx + ty * dy
            guard along >= 0 && along <= dodgeLookahead else { continue }   // nur Schüsse, die heranfliegen
            var perpx = tx - dx * along, perpy = ty - dy * along
            let pd = hypot(perpx, perpy)
            guard pd < dodgeRadius else { continue }
            if pd < 1.0 { perpx = -dy; perpy = dx }   // genau auf der Linie: eine Seite wählen
            let n = max(1.0, hypot(perpx, perpy))
            let w = 1.0 - pd / dodgeRadius
            fx += perpx / n * dodgeStrength * w
            fy += perpy / n * dodgeStrength * w
        }

        // 3. Im Bild halten (weiche Grenzen).
        let halfW = screenSize.width * 0.5, halfH = screenSize.height * 0.5
        let limX = halfW * 0.80, limTop = halfH * 0.86, limBot = -halfH * 0.34
        if position.x >  limX  { fx -= boundsStrength * (position.x - limX) }
        if position.x < -limX  { fx += boundsStrength * (-limX - position.x) }
        if position.y >  limTop { fy -= boundsStrength * (position.y - limTop) }
        if position.y <  limBot { fy += boundsStrength * (limBot - position.y) }

        // Integrieren, dämpfen (frameraten-normiert), Geschwindigkeit deckeln.
        moveVelocity.x += fx * CGFloat(dt)
        moveVelocity.y += fy * CGFloat(dt)
        let fr = pow(moveFriction, CGFloat(dt) * 60.0)
        moveVelocity.x *= fr
        moveVelocity.y *= fr
        let sp = hypot(moveVelocity.x, moveVelocity.y)
        if sp > maxMoveSpeed {
            moveVelocity.x *= maxMoveSpeed / sp
            moveVelocity.y *= maxMoveSpeed / sp
        }
        position.x += moveVelocity.x * CGFloat(dt)
        position.y += moveVelocity.y * CGFloat(dt)
    }

    /// Fährt `mouthProgress` (0..1) sanft zum Ziel. Der Schrei-Mund ist in der Textur dauerhaft offen
    /// – dieser Wert steuert daher NICHT mehr die Optik, sondern nur noch die Boss-Stimme
    /// (`mouthOpenness`): sie schwillt beim Speien an und klingt beim Rückzug ab.
    private func advanceMouth(toward target: CGFloat, dt: TimeInterval) {
        let rate = CGFloat(1.0 / mouthMoveDuration)
        if mouthProgress < target {
            mouthProgress = min(target, mouthProgress + rate * CGFloat(dt))
        } else if mouthProgress > target {
            mouthProgress = max(target, mouthProgress - rate * CGFloat(dt))
        }
    }

    private func trackEyes(towards shipWorld: CGPoint) {
        guard scene != nil, leftPupil != nil else { return }
        let localShip = art.convert(shipWorld, from: scene!)
        positionPupil(leftPupil, socket: leftSocketCenter, towards: localShip)
        positionPupil(rightPupil, socket: rightSocketCenter, towards: localShip)
    }

    private func positionPupil(_ pupil: SKShapeNode, socket: CGPoint, towards localShip: CGPoint) {
        let dx = localShip.x - socket.x
        let dy = localShip.y - socket.y
        let d = hypot(dx, dy)
        let maxOffset: CGFloat = 6.0
        if d < 0.001 {
            pupil.position = socket
        } else {
            let k = min(maxOffset, d) / d
            pupil.position = CGPoint(x: socket.x + dx * k, y: socket.y + dy * k)
        }
    }

    private func showHitFeedback() {
        // Kurzer Weiß-Flash über die getracte Kontur (Sprite-Einfärbung).
        headSprite?.run(.sequence([
            .colorize(with: .white, colorBlendFactor: 0.85, duration: 0.05),
            .colorize(withColorBlendFactor: 0.0, duration: 0.10)
        ]))
    }

    /// Zeigt die Schadens-Risse abhängig vom verbleibenden Lebensanteil (skaliert mit `maxHits`):
    /// ab ≤66 % ein Auge, ab ≤33 % zweites Auge + Kiefer.
    private func updateDamageVisual() {
        let frac = Double(hitsRemaining) / Double(max(1, maxHits))
        leftEyeCrack.isHidden = frac > 0.66
        rightEyeCrack.isHidden = frac > 0.33
        jawCrack.isHidden = frac > 0.33
    }

    /// Kurzer Materialisier-Blitz (Ring) im Mund-Mittelpunkt, wenn ein UFO ausgespien wird.
    private func showMouthSpawnFlash() {
        guard scene != nil else { return }
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.position = mouthLocal
        ring.strokeColor = eyeGlow
        ring.fillColor = .clear
        ring.lineWidth = 2
        VectorGlowRenderer.markStroke(ring)
        art.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 2.6, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent()
        ]))
    }

    // MARK: - Grafik-Aufbau (vektorisierte Kontur-Textur)

    /// Baut den Kopf-Boss aus der getracten Zardoz-Textur (Silber auf transparent) als ein zentriertes
    /// Sprite und legt darüber die beweglichen Glüh-Pupillen sowie die (zunächst versteckten)
    /// Schadens-Risse. Aus den normierten Augen-/Mund-Koordinaten werden die lokalen Sockel- und
    /// Mund-Positionen berechnet (Textur-y nach unten -> Szenen-y nach oben gespiegelt).
    private func buildArt() {
        guard let tex = ArtTexture.load("zardoz_head") else {
            buildFallbackArt()
            return
        }
        let texSize = tex.size()
        let aspect = texSize.width / max(1.0, texSize.height)
        let size = CGSize(width: headHeight * aspect, height: headHeight)

        let sprite = SKSpriteNode(texture: tex, size: size)
        art.addChild(sprite)
        headSprite = sprite

        // Norm-Koordinate -> lokale Szenen-Koordinate (Sprite ist um (0,0) zentriert, y nach oben).
        func local(_ n: CGPoint) -> CGPoint {
            CGPoint(x: (n.x - 0.5) * size.width, y: (0.5 - n.y) * size.height)
        }
        leftSocketCenter = local(leftEyeNorm)
        rightSocketCenter = local(rightEyeNorm)
        mouthLocal = local(mouthNorm)

        // Bewegliche Glüh-Pupillen über den (in die Textur gestickten) Augen – sie verdecken die
        // statischen Pupillen und folgen dem Schiff (der „die Augen bewegen sich noch"-Wunsch).
        leftPupil = pupilNode(at: leftSocketCenter)
        rightPupil = pupilNode(at: rightSocketCenter)
        art.addChild(leftPupil)
        art.addChild(rightPupil)

        // Schadens-Risse (rot, anfangs versteckt) an Augen und Kiefer.
        leftEyeCrack = crackNode(around: leftSocketCenter)
        rightEyeCrack = crackNode(around: rightSocketCenter)
        jawCrack = crackNode(around: CGPoint(x: mouthLocal.x, y: mouthLocal.y - size.height * 0.10))
        leftEyeCrack.isHidden = true
        rightEyeCrack.isHidden = true
        jawCrack.isHidden = true
        art.addChild(leftEyeCrack)
        art.addChild(rightEyeCrack)
        art.addChild(jawCrack)
    }

    /// Notnagel ohne Textur: schlichte Stein-Kontur + Glüh-Augen, damit Spiel/Tests nie leer laufen.
    private func buildFallbackArt() {
        let circle = SKShapeNode(circleOfRadius: collisionRadius)
        circle.fillColor = SKColor(white: 0.06, alpha: 1.0)
        circle.strokeColor = stone
        circle.lineWidth = 3
        VectorGlowRenderer.markStroke(circle)
        art.addChild(circle)
        leftSocketCenter = CGPoint(x: -collisionRadius * 0.35, y: collisionRadius * 0.2)
        rightSocketCenter = CGPoint(x: collisionRadius * 0.35, y: collisionRadius * 0.2)
        mouthLocal = CGPoint(x: 0, y: -collisionRadius * 0.3)
        headSprite = SKSpriteNode(color: .clear, size: .zero)
        leftPupil = pupilNode(at: leftSocketCenter)
        rightPupil = pupilNode(at: rightSocketCenter)
        art.addChild(leftPupil)
        art.addChild(rightPupil)
        leftEyeCrack = crackNode(around: leftSocketCenter); leftEyeCrack.isHidden = true
        rightEyeCrack = crackNode(around: rightSocketCenter); rightEyeCrack.isHidden = true
        jawCrack = crackNode(around: mouthLocal); jawCrack.isHidden = true
        art.addChild(leftEyeCrack); art.addChild(rightEyeCrack); art.addChild(jawCrack)
    }

    /// Eine glühende, bewegliche Pupille: heller Hof + roter Kern.
    private func pupilNode(at center: CGPoint) -> SKShapeNode {
        let halo = SKShapeNode(circleOfRadius: 7.5)
        halo.fillColor = eyeGlow.withAlphaComponent(0.35)
        halo.strokeColor = .clear
        let core = SKShapeNode(circleOfRadius: 4.5)
        core.fillColor = pupilCol
        core.strokeColor = eyeGlow
        core.lineWidth = 1.0
        VectorGlowRenderer.markStroke(core)
        VectorGlowRenderer.markFill(core)
        halo.addChild(core)
        halo.position = center
        return halo
    }

    /// Ein kleiner roter Riss-Zickzack um `center` (eine Schadens-Stufe).
    private func crackNode(around center: CGPoint) -> SKShapeNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: center.x - 10, y: center.y + 8))
        p.addLine(to: CGPoint(x: center.x - 2, y: center.y + 1))
        p.addLine(to: CGPoint(x: center.x - 7, y: center.y - 4))
        p.addLine(to: CGPoint(x: center.x + 4, y: center.y - 11))
        let node = SKShapeNode(path: p)
        node.strokeColor = crackRed
        node.lineWidth = 2.0
        node.lineJoin = .round
        node.fillColor = .clear
        VectorGlowRenderer.markStroke(node)
        return node
    }
}
