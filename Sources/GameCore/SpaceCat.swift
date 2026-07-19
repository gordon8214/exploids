import SpriteKit

/// Die **Weltraumkatze** – ein Miniboss (kleiner als der Kopf-Boss „Der Götze"). Sie treibt sich
/// nicht sinnlos herum, sondern agiert gezielt: Sie pirscht sich an den Spieler heran, sucht dabei
/// **Deckung hinter großen Asteroiden** und weicht Objekten sowie Spielerschüssen aus. Ihr Angriff
/// sind die **Laseraugen**: ein **Zwillings-Laser** (zwei parallele, längere, langsame Streifen) mit
/// **vorausberechnetem Zielen** (Predictive Aim) – fliegt der Spieler unbeirrt weiter, wird er
/// getroffen. Ausgeglichen wird das durch die geringe Schuss-Frequenz und die halbe Schuss-
/// geschwindigkeit.
///
/// Ablauf: **dreimal** je ein Doppelschuss-Versuch, **dazwischen jeweils ausweichen**; danach
/// **Flucht zum Bildschirmrand – ohne Wrap** (sie verschwindet und kommt nicht zurück).
///
/// Die Grafik ist reines Retro-Vektor-Linienwerk (y nach oben = SpriteKit-Standard, daher – anders
/// als beim Kopf-Boss – keine Spiegelung nötig). Mehrere `SKShapeNode`-Kinder hängen direkt im Node.
public final class SpaceCat: SKNode {

    // MARK: - Phasen des Lebenszyklus

    public enum Phase: Sendable, Equatable {
        case entering        // schwebt vom Bildrand herein
        case stalking        // pirscht sich an, sucht Deckung, zielt – bis der Doppelschuss kommt
        case repositioning   // weicht nach einem Schuss aus, bevor der nächste Versuch folgt
        case fleeing         // flieht nach dem dritten Versuch zum Rand (kein Wrap)
    }

    // MARK: - Zustand

    public private(set) var phase: Phase = .entering

    /// Treffer bis zur Zerstörung – zentral justierbar (Miniboss). Default 3 (mehr als ein normales
    /// UFO mit 1 Treffer, aber deutlich weniger als der Kopf-Boss mit 10).
    public static var hitsToDestroy: Int = 3
    /// Verbleibende Treffer bis zur Zerstörung.
    public private(set) var hitsRemaining: Int = SpaceCat.hitsToDestroy

    /// True, sobald die Katze nach der Flucht komplett aus dem Bild ist (von der GameScene entfernt).
    public private(set) var isFinished: Bool = false

    /// Punkte fürs Zerstören – zwischen kleinem UFO (500) und Kopf-Boss (2000).
    public let pointValue: Int = 750

    /// Ungefährer Kollisionsradius (Kreis) in Szenen-Einheiten. Deckt die ganze sichtbare Katze
    /// (Kopf + Körper bis zur Basis) ab – auf die getracte Kontur-Größe (artHeight 96) abgestimmt,
    /// damit sie „überall treffbar" ist (vorher 26 = nur der mittlere Rumpf -> kaum zu treffen).
    public let collisionRadius: CGFloat = 42.0

    /// Zeitpunkt des letzten Laserbeam-Treffers (für die Treffer-Drosselung des Dauer-Strahls,
    /// damit die Katze nicht in Sekundenbruchteilen zerschmilzt). Wird von der GameScene gesetzt.
    public var lastBeamHitTime: TimeInterval = 0.0

    /// Geschwindigkeit der Augen-Laser: **halbe Spielerschuss-Geschwindigkeit** (Spieler = 600).
    public static let laserSpeed: CGFloat = 300.0

    // MARK: - Tuning (für Tests/Justierung überschreibbar)

    /// Dauer des Anpirschens/Zielens, bis der Doppelschuss ausgelöst wird (bewusst träge = niedrige
    /// Frequenz; gibt dem Spieler ein Reaktionsfenster).
    public var aimDuration: TimeInterval = 1.6
    /// Dauer des Ausweichens zwischen zwei Schuss-Versuchen.
    public var repositionDuration: TimeInterval = 1.3
    /// Gesamtzahl der Doppelschuss-Versuche, danach Flucht.
    public var totalAttacks: Int = 3

    // MARK: - Intern

    private let screenSize: CGSize
    private let entryTarget: CGPoint

    private var stateTime: TimeInterval = 0.0
    private var attacksRemaining: Int
    private var fleeDirX: CGFloat = 1.0   // Richtung der Flucht (+1 = nach rechts raus)

    // Bewegung (Steering) – eigene, gedeckelte Geschwindigkeit. Nimble, aber nicht irrwitzig.
    private var moveVelocity: CGPoint = .zero
    private let maxMoveSpeed: CGFloat = 230.0
    private let enterSpeed: CGFloat = 240.0
    private let fleeSpeed: CGFloat = 360.0
    private let attackDistance: CGFloat = 280.0   // bevorzugter Schuss-Abstand zum Schiff
    private let minDistance: CGFloat = 170.0      // näher will die Katze nicht heran
    private let approachStrength: CGFloat = 520.0
    private let coverStrength: CGFloat = 360.0    // Sog Richtung „hinter einem Asteroiden"
    private let coverSearchRange: CGFloat = 360.0 // nur Asteroiden in dieser Nähe als Deckung nutzen
    private let avoidBuffer: CGFloat = 18.0       // Abstand, ab dem Objekten ausgewichen wird
    // Sicherheitsabstand hinter der Deckung. MUSS größer als `avoidBuffer` sein, sonst läge der
    // angesteuerte Deckungspunkt INNERHALB des Abstoßungs-Radius → die Ausweich-Kraft würde die
    // Katze sofort wieder wegdrücken (Dauer-Oszillation). Daher bewusst > avoidBuffer.
    private let coverMargin: CGFloat = 28.0
    private let avoidStrength: CGFloat = 900.0
    private let dodgeStrength: CGFloat = 1100.0   // Ausweichen vor Spielerschüssen
    private let dodgeRadius: CGFloat = 70.0       // seitlicher Gefahren-Korridor um einen Schuss
    private let dodgeLookahead: CGFloat = 240.0   // wie weit voraus Schüsse beachtet werden
    private let boundsStrength: CGFloat = 26.0    // hält sie im sichtbaren Bereich (außer bei Flucht)
    private let moveFriction: CGFloat = 0.86      // Dämpfung pro 1/60 s, frameraten-normiert

    // Schuss-Geometrie. Der Laser-Ursprung ist jetzt das echte (getracte) Auge der Katzen-Kontur.
    private let eyeSpacing: CGFloat = 7.0         // halber Versatz der zwei parallelen Laser ums Auge
    private let maxLeadTime: CGFloat = 2.0        // Deckel für die Predictive-Aim-Vorhaltezeit (s)

    // Darstellung: vektorisierte Kontur als Textur (Art/space_cat.png). Diese Konstanten verankern
    // Kollisionskreis (Körper+Kopf) und Augen-Laser-Ursprung relativ zur getracten Grafik – bewusst
    // zentral und im Playtest justierbar. `*Norm` sind normierte Texturkoordinaten (0..1, y nach unten).
    private let artHeight: CGFloat = 96.0                    // Bildhöhe der Katze in Szenen-Einheiten
    private let bodyCenterNorm = CGPoint(x: 0.72, y: 0.52)   // Körper/Kopf-Schwerpunkt -> auf den Ursprung (= Kollisionsmitte)
    private let eyeNorm = CGPoint(x: 0.885, y: 0.175)        // Auge (Laser-Ursprung), Blick nach rechts

    // Fallback-Farbe, falls die Textur fehlt (dann simple Vektor-Silhouette).
    private let body = SKColor(red: 0.72, green: 0.42, blue: 1.0, alpha: 1.0)

    // Grafik-Referenzen: zwei gespiegelte Kontur-Sprites für den Richtungswechsel (Crossfade).
    private var catRight: SKSpriteNode!
    private var catLeft: SKSpriteNode!
    private var facingRight = true
    /// Lokaler Augen-Ursprung bei Blick nach rechts (in `buildArt` aus den Norm-Koords berechnet).
    private var eyeOffsetRight: CGPoint = .zero

    // MARK: - Rückgabe beim Schuss

    /// Beschreibung eines Doppelschusses: zwei **parallele** Laser-Ursprünge und der gemeinsame
    /// Winkel. Die GameScene baut daraus zwei `Laser` vom Typ `.catEye`.
    public struct TwinLaserShot: Sendable {
        public let origins: [CGPoint]   // genau zwei, parallel versetzt
        public let angle: CGFloat
    }

    // MARK: - Init

    /// Erzeugt eine Weltraumkatze für eine gegebene Szenengröße. Sie startet komplett außerhalb des
    /// Bildrands (links oder rechts) und schwebt in den sichtbaren Bereich; danach übernimmt die KI.
    public init(screenSize: CGSize, startOnLeft: Bool, using rng: inout GameRandom) {
        self.screenSize = screenSize
        self.attacksRemaining = totalAttacks
        let halfW = screenSize.width / 2
        let entryY = CGFloat.random(in: -screenSize.height * 0.25...screenSize.height * 0.25, using: &rng)
        self.entryTarget = CGPoint(x: startOnLeft ? -halfW * 0.45 : halfW * 0.45, y: entryY)
        super.init()

        self.position = CGPoint(x: startOnLeft ? -halfW - 50.0 : halfW + 50.0, y: entryY)
        self.zPosition = 5
        buildArt()
    }

    /// Convenience-Initializer ohne Seed für Tests/Helfer — würfelt aus dem System-RNG.
    /// NICHT im deterministischen Gameplay-Pfad verwenden (dafür den Initializer mit `using rng:`).
    public convenience init(screenSize: CGSize, startOnLeft: Bool) {
        var throwaway = GameRandom(seed: GameRandom.systemSeed())
        self.init(screenSize: screenSize, startOnLeft: startOnLeft, using: &throwaway)
    }

    public required init?(coder aDecoder: NSCoder) {
        self.screenSize = CGSize(width: 1024, height: 768)
        self.attacksRemaining = 3
        self.entryTarget = CGPoint(x: 200, y: 0)
        super.init(coder: aDecoder)
    }

    // MARK: - Öffentliche API (Spiel-Logik)

    /// Schreitet den Zustandsautomaten um `deltaTime` voran.
    /// - Parameter coverObjects: Positionen + Radien geeigneter Deckungsobjekte (große/mittlere
    ///   Asteroiden), hinter die sich die Katze stellt.
    /// - Parameter laserThreats: Position + Geschwindigkeit der Spielerschüsse (zum Ausweichen).
    /// - Parameter canFire: Ob die Katze feuern darf (i.d.R. nur bei sichtbarem Schiff). Ist sie
    ///   `false`, hält die Katze den Ziel-Countdown an und bewegt sich nur – so wird kein Angriffs-
    ///   versuch „verschwendet", während der Spieler tot/im Respawn ist.
    /// - Returns: Einen `TwinLaserShot`, falls die Katze **in diesem Frame** feuert, sonst `nil`.
    @discardableResult
    public func update(deltaTime: TimeInterval, shipPosition: CGPoint, shipVelocity: CGPoint,
                       coverObjects: [(position: CGPoint, radius: CGFloat)] = [],
                       laserThreats: [(position: CGPoint, velocity: CGPoint)] = [],
                       canFire: Bool = true,
                       using rng: inout GameRandom) -> TwinLaserShot? {
        var shot: TwinLaserShot? = nil

        // Blickrichtung an das Schiff koppeln (außer auf der Flucht, wo sie geradlinig rausgleitet).
        if phase != .fleeing { updateFacing(towards: shipPosition.x) }

        switch phase {
        case .entering:
            moveToward(entryTarget, speed: enterSpeed, dt: deltaTime)
            if position.distance(to: entryTarget) < 6.0 {
                position = entryTarget
                enterStalking()
            }

        case .stalking:
            updateMovement(dt: deltaTime, shipPos: shipPosition, cover: coverObjects,
                           threats: laserThreats, seekCover: true)
            // Ziel-Countdown nur fortschreiten lassen, wenn auch wirklich gefeuert werden darf.
            if canFire {
                stateTime += deltaTime
                if stateTime >= aimDuration {
                    shot = makeTwinShot(shipPos: shipPosition, shipVel: shipVelocity)
                    flashEyes()
                    attacksRemaining -= 1
                    if attacksRemaining > 0 {
                        enterRepositioning(awayFrom: shipPosition, using: &rng)
                    } else {
                        enterFleeing(awayFrom: shipPosition)
                    }
                }
            }

        case .repositioning:
            updateMovement(dt: deltaTime, shipPos: shipPosition, cover: coverObjects,
                           threats: laserThreats, seekCover: false)
            stateTime += deltaTime
            if stateTime >= repositionDuration {
                enterStalking()
            }

        case .fleeing:
            // Geradlinig zum Rand hinaus – keine weiteren Manöver, kein Wrap.
            position.x += fleeDirX * fleeSpeed * CGFloat(deltaTime)
            let threshold = screenSize.width / 2 + 60.0
            if abs(position.x) > threshold {
                isFinished = true
            }
        }

        return shot
    }

    /// Verarbeitet einen Spieler-Treffer. Gibt `true` zurück, wenn die Katze dadurch zerstört ist.
    @discardableResult
    public func registerHit() -> Bool {
        guard hitsRemaining > 0 else { return true }
        hitsRemaining -= 1
        flashEyes()
        return hitsRemaining <= 0
    }

    /// Für Tests: überspringt die Einschweb-Phase und beginnt sofort am Lauer-Ort mit dem Anpirschen.
    public func beginStalkingForTesting() {
        position = entryTarget
        enterStalking()
    }

    // MARK: - Phasenübergänge

    private func enterStalking() {
        phase = .stalking
        stateTime = 0.0
    }

    private func enterRepositioning(awayFrom shipPos: CGPoint, using rng: inout GameRandom) {
        phase = .repositioning
        stateTime = 0.0
        // Seitlicher Ausweich-Impuls senkrecht zur Linie Katze→Schiff (zufällige Seite).
        let dx = position.x - shipPos.x, dy = position.y - shipPos.y
        let d = max(1.0, hypot(dx, dy))
        let perpX = -dy / d, perpY = dx / d
        let side: CGFloat = Bool.random(using: &rng) ? 1.0 : -1.0
        moveVelocity.x += perpX * side * maxMoveSpeed
        moveVelocity.y += perpY * side * maxMoveSpeed
    }

    private func enterFleeing(awayFrom shipPos: CGPoint) {
        phase = .fleeing
        // Zum Rand fliehen, der vom Schiff weg zeigt (sonst müsste sie am Spieler vorbei).
        fleeDirX = (position.x >= shipPos.x) ? 1.0 : -1.0
    }

    // MARK: - Schuss (Predictive Aim, Zwillings-Laser)

    private func makeTwinShot(shipPos: CGPoint, shipVel: CGPoint) -> TwinLaserShot {
        // Flugzeit iterativ schätzen und das Ziel entsprechend voraushalten. Die Vorhaltezeit wird
        // gedeckelt: Ist das Schiff schneller als der Laser (Ship.maxVelocity 350 > laserSpeed 300),
        // gibt es keinen exakten Abfangpunkt – ohne Deckel würde `t` davonlaufen und der Schuss
        // sinnlos weit ins Leere zielen. Der Deckel hält die Vorhaltung in plausiblem Rahmen.
        var t = min(maxLeadTime, position.distance(to: shipPos) / SpaceCat.laserSpeed)
        for _ in 0..<2 {
            let pred = CGPoint(x: shipPos.x + shipVel.x * t, y: shipPos.y + shipVel.y * t)
            t = min(maxLeadTime, position.distance(to: pred) / SpaceCat.laserSpeed)
        }
        let predicted = CGPoint(x: shipPos.x + shipVel.x * t, y: shipPos.y + shipVel.y * t)
        // Aus dem Auge zielen (nicht aus der Körpermitte) – die Laser kommen sichtbar aus dem Auge.
        let eye = eyeWorldPosition()
        let angle = atan2(predicted.y - eye.y, predicted.x - eye.x)

        // Zwei parallele Ursprünge: ums Auge herum, senkrecht zum Schuss leicht versetzt.
        let dirX = cos(angle), dirY = sin(angle)
        let perpX = -dirY, perpY = dirX
        let a = CGPoint(x: eye.x + perpX * eyeSpacing, y: eye.y + perpY * eyeSpacing)
        let b = CGPoint(x: eye.x - perpX * eyeSpacing, y: eye.y - perpY * eyeSpacing)
        return TwinLaserShot(origins: [a, b], angle: angle)
    }

    /// Weltposition des Augen-Ursprungs. Die Seite (links/rechts) folgt der aktuellen Blickrichtung;
    /// bei Blick nach links wird der lokale x-Versatz gespiegelt (wie die gespiegelte Kontur).
    private func eyeWorldPosition() -> CGPoint {
        let ex = facingRight ? eyeOffsetRight.x : -eyeOffsetRight.x
        return CGPoint(x: position.x + ex, y: position.y + eyeOffsetRight.y)
    }

    // MARK: - Bewegung / Steering
    // (`moveToward`/`distance` liegen zentral in VectorMath.swift — waren hier und in
    // FloatingHead identisch dupliziert.)

    /// Steering aus mehreren Kräften: Abstand zum Schiff halten, Deckung suchen, Schüssen ausweichen,
    /// Objekten ausweichen, im Bild bleiben. Bewusst gedeckelt – fordernd, aber nicht unfair.
    private func updateMovement(dt: TimeInterval, shipPos: CGPoint,
                                cover: [(position: CGPoint, radius: CGFloat)],
                                threats: [(position: CGPoint, velocity: CGPoint)],
                                seekCover: Bool) {
        var fx: CGFloat = 0, fy: CGFloat = 0

        // 1. Schuss-Abstand zum Schiff halten (zu weit → ran, zu nah → weg).
        let ax = shipPos.x - position.x, ay = shipPos.y - position.y
        let d = max(1.0, hypot(ax, ay))
        if d > attackDistance {
            let w = min(1.0, (d - attackDistance) / attackDistance)
            fx += ax / d * approachStrength * w
            fy += ay / d * approachStrength * w
        } else if d < minDistance {
            let w = (minDistance - d) / minDistance
            fx -= ax / d * approachStrength * w
            fy -= ay / d * approachStrength * w
        }

        // 2. Deckung suchen: hinter den nächsten geeigneten Asteroiden (relativ zum Schiff) stellen.
        if seekCover, let best = nearestCover(cover, shipPos: shipPos) {
            let toShipX = shipPos.x - best.position.x, toShipY = shipPos.y - best.position.y
            let dl = max(1.0, hypot(toShipX, toShipY))
            // „Hinter" dem Asteroiden = auf der vom Schiff abgewandten Seite.
            let behind = CGPoint(
                x: best.position.x - toShipX / dl * (best.radius + collisionRadius + coverMargin),
                y: best.position.y - toShipY / dl * (best.radius + collisionRadius + coverMargin)
            )
            let cx = behind.x - position.x, cy = behind.y - position.y
            let cd = max(1.0, hypot(cx, cy))
            fx += cx / cd * coverStrength
            fy += cy / cd * coverStrength
        }

        // 3. Spielerschüssen ausweichen (seitlich aus der Bahn gleiten).
        for tr in threats {
            let dirLen = hypot(tr.velocity.x, tr.velocity.y)
            guard dirLen > 0.001 else { continue }
            let vx = tr.velocity.x / dirLen, vy = tr.velocity.y / dirLen
            let rx = position.x - tr.position.x, ry = position.y - tr.position.y
            let along = rx * vx + ry * vy
            guard along >= 0 && along <= dodgeLookahead else { continue }   // nur heranfliegende Schüsse
            var perpx = rx - vx * along, perpy = ry - vy * along
            let pd = hypot(perpx, perpy)
            guard pd < dodgeRadius else { continue }
            if pd < 1.0 { perpx = -vy; perpy = vx }   // genau auf der Linie: eine Seite wählen
            let n = max(1.0, hypot(perpx, perpy))
            let w = 1.0 - pd / dodgeRadius
            fx += perpx / n * dodgeStrength * w
            fy += perpy / n * dodgeStrength * w
        }

        // 4. Objekten ausweichen (nicht hineinfahren): von zu nahen Asteroiden wegdrücken.
        for obj in cover {
            let ox = position.x - obj.position.x, oy = position.y - obj.position.y
            let od = hypot(ox, oy)
            let safe = obj.radius + collisionRadius + avoidBuffer
            if od < safe && od > 0.001 {
                let w = (safe - od) / safe
                fx += ox / od * avoidStrength * w
                fy += oy / od * avoidStrength * w
            }
        }

        // 5. Im Bild halten (weiche Grenzen).
        let halfW = screenSize.width * 0.5, halfH = screenSize.height * 0.5
        let limX = halfW * 0.86, limY = halfH * 0.78
        if position.x >  limX { fx -= boundsStrength * (position.x - limX) }
        if position.x < -limX { fx += boundsStrength * (-limX - position.x) }
        if position.y >  limY { fy -= boundsStrength * (position.y - limY) }
        if position.y < -limY { fy += boundsStrength * (-limY - position.y) }

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

    /// Liefert den nächstgelegenen Asteroiden im Suchradius, der als Deckung taugt.
    private func nearestCover(_ cover: [(position: CGPoint, radius: CGFloat)],
                              shipPos: CGPoint) -> (position: CGPoint, radius: CGFloat)? {
        var best: (position: CGPoint, radius: CGFloat)? = nil
        var bestD = coverSearchRange
        for obj in cover {
            let dd = position.distance(to: obj.position)
            if dd < bestD {
                bestD = dd
                best = obj
            }
        }
        return best
    }

    // MARK: - Grafik (vektorisierte Kontur-Textur)

    /// Kurzes Hell-Aufpulsen der Kontur (beim Feuern und bei einem Treffer): die violetten Linien
    /// blitzen kurz weiß auf (über `colorBlendFactor` der Sprites).
    private func flashEyes() {
        for sprite in [catRight, catLeft] {
            guard let sprite else { continue }
            sprite.run(.sequence([
                .colorize(with: .white, colorBlendFactor: 0.9, duration: 0.05),
                .colorize(withColorBlendFactor: 0.0, duration: 0.18)
            ]))
        }
    }

    /// Aktualisiert die Blickrichtung anhand der Schiffsposition und blendet bei einem Wechsel weich
    /// in die gespiegelte Kontur über (der gewünschte „Richtungswechsel ohne 3D"). Eine Hysterese
    /// (30 pt) verhindert Zittern, wenn das Schiff fast senkrecht über/unter der Katze steht.
    private func updateFacing(towards shipX: CGFloat) {
        guard catRight != nil, catLeft != nil else { return }
        let want = shipX >= position.x
        guard want != facingRight, abs(shipX - position.x) > 30.0 else { return }
        facingRight = want
        catRight.removeAllActions()
        catLeft.removeAllActions()
        catRight.run(.fadeAlpha(to: facingRight ? 1.0 : 0.0, duration: 0.22))
        catLeft.run(.fadeAlpha(to: facingRight ? 0.0 : 1.0, duration: 0.22))
    }

    /// Baut die Katze als zwei gespiegelte Kontur-Sprites (eines blickt nach rechts, eines nach
    /// links). Der Körper/Kopf-Schwerpunkt wird auf den Knoten-Ursprung gelegt – dort sitzt der
    /// Kollisionskreis; der lange Schweif ragt frei darüber hinaus. Aus den Norm-Koordinaten wird
    /// zugleich der lokale Augen-Ursprung für die Laser berechnet.
    private func buildArt() {
        guard let tex = ArtTexture.load("space_cat") else {
            buildFallbackArt()
            return
        }
        let texSize = tex.size()
        let aspect = texSize.width / max(1.0, texSize.height)
        let size = CGSize(width: artHeight * aspect, height: artHeight)

        // Sprite so verschieben, dass der Körper/Kopf-Schwerpunkt im Knoten-Ursprung (0,0) liegt.
        // Texturkoordinaten haben y nach unten, Szenen-Koordinaten y nach oben -> y-Term spiegeln.
        let offset = CGPoint(x: (0.5 - bodyCenterNorm.x) * size.width,
                             y: (bodyCenterNorm.y - 0.5) * size.height)

        let right = SKSpriteNode(texture: tex, size: size)
        right.position = offset
        addChild(right)
        catRight = right

        let left = SKSpriteNode(texture: tex, size: size)
        left.position = offset
        left.xScale = -1.0          // gespiegelte Kontur (Blick nach links)
        left.alpha = 0.0
        addChild(left)
        catLeft = left

        // Lokaler Augen-Ursprung bei Blick nach rechts (Norm-Koord -> lokale Szenen-Koord, y oben).
        eyeOffsetRight = CGPoint(x: offset.x + (eyeNorm.x - 0.5) * size.width,
                                 y: offset.y + (0.5 - eyeNorm.y) * size.height)
    }

    /// Notnagel ohne Textur: eine einfache violette Kontur, damit Spiel/Tests nie leer laufen.
    private func buildFallbackArt() {
        let dot = SKShapeNode(circleOfRadius: collisionRadius)
        dot.strokeColor = body
        dot.fillColor = .clear
        dot.lineWidth = 2.0
        VectorGlowRenderer.markStroke(dot)
        addChild(dot)
        // Dummy-Sprites, damit flashEyes/updateFacing nicht crashen.
        catRight = SKSpriteNode(color: .clear, size: .zero)
        catLeft = SKSpriteNode(color: .clear, size: .zero)
        eyeOffsetRight = CGPoint(x: collisionRadius * 0.6, y: collisionRadius * 0.4)
    }
}
