# Exploids

**🌐 Sprache / Language:** [English](README.md) · [Deutsch](README.de.md)

<p align="center"><img src="Icon/icon_1024.png" width="180" alt="Exploids App-Icon"></p>

Ein nativer macOS-Arcade-Shooter im Asteroids-Stil (Swift 6 · SpriteKit) mit einem an den Commodore 64 angelehnten Vektor-Look — in moderner hoher Auflösung und butterweicher Bildrate (Apple Silicon, ProMotion 120 Hz). Fast jede Grafik ist prozedurale Vektor-Geometrie — nur die beiden Bosse nutzen getracte Vektor-Konturen als Texturen — und jeder Soundeffekt wird in Echtzeit synthetisiert; mitgeliefert sind zwei Chiptune-Musikstücke, die Boss-Texturen und ein optionales Paket aufgenommener Soundeffekte. Drei Spielmodi, neun Power-Ups, Gravitationsfelder, gegnerische UFOs, zwei Bosse, ein Pixel-Font-HUD und ein deterministisches Replay-System, das Promo-GIFs headless rendern kann.

> Der Text im Spiel ist auf Englisch.

## Download

**[➜ Aktuelles signiertes & notarisiertes DMG herunterladen](https://github.com/DanielMuellerIR/exploids/releases/latest)** — öffnen, *Exploids* in den Programme-Ordner ziehen und doppelklicken. Mit Developer ID signiert und von Apple notarisiert, öffnet also ohne Gatekeeper-Warnung. Benötigt macOS 11 oder neuer (Apple Silicon).

Lieber selbst aus dem Quellcode bauen? Siehe [Bauen & starten](#bauen--starten-kommandozeile--headless-tauglich) weiter unten.

## Screenshots

<p align="center"><img src="screenshots/sc0.jpg" width="860" alt="Survival-Modus in vollem Fluss — das Schiff feuert einen regenbogenfarbenen Schuss-Strom an einem violetten Gravitationsfeld vorbei, während Asteroiden und ein gegnerisches UFO heranrücken"></p>

| Option-Drohne + Schild | Glossar im Spiel |
|:--:|:--:|
| ![Asteroidenfeld mit aufgesammelter Option-Drohne, Schiff mit Schild und geschrumpft](screenshots/sc1.jpg) | ![Glossar der Objekte und Power-Ups](screenshots/sc3.jpg) |
| **Laserstrahl** | **Gravitationsfeld + Bombe** |
| ![Der gehaltene Laserstrahl fegt über das Feld](screenshots/sc2.jpg) | ![Ein Gravitationsfeld verzerrt den Raum, während eine Bombe zündet](screenshots/sc4.jpg) |

## Bauen & starten (Kommandozeile / headless-tauglich)

Kein Xcode-Projekt — ein Swift-Package-Manager-Executable, das zu einem `.app`-Bundle kompiliert wird. Die gesamte Toolchain ist skriptbar (praktisch für Automatisierung und KI-Agenten):

```bash
./build-app.sh                                   # baut -> Exploids.app (doppelklickbar)
open Exploids.app                                # starten
.build/release/exploids                          # nackte Binary starten (Logs im Terminal)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # die Unit-Tests laufen lassen
```

### Signiertes + notarisiertes DMG

```bash
bash wrappers/sign-and-release.sh                # -> build/Exploids-<version>.dmg, Gatekeeper-sauber
bash wrappers/sign-and-release.sh --publish      # setzt zusätzlich Tag + lädt das DMG zu GitHub Releases
```

## Spielmodi

Auswahl im Startbildschirm (▲/▼ wechseln, ◀/▶ für den Ancient-/Mad-Startlevel, Leertaste startet):

- **Ancient Asteroids** — der ursprüngliche Exploids-Modus. Festes Spielfeld; Objekte laufen über die Bildschirmränder hinaus und kommen gegenüber wieder herein.
- **Mad Meteoroids** — das gesamte Feld (Asteroiden, Gravitationsfelder, Power-Ups, Sternenhimmel) rotiert fortlaufend um die Bildschirmmitte, während das Schiff ausgenommen bleibt (Crazy-Comets-Stil). Die Rotationsgeschwindigkeit steigt mit dem Level, mit geplanten Richtungswechseln und gelegentlichen „Record-Scratch"-Rucklern in höheren Leveln.
- **Classic Asteroids** — ein eigener, vom Einspieler-Arcade-Spiel von 1979 inspirierter Regelsatz: monochrome weiße Spielvektoren, Wellen normaler Brocken, vier Einzelschüsse, horizontal fliegende große/kleine Untertassen, drei Startschiffe, ein Bonusschiff je 10.000 Punkte und `H` für Hyperspace. Classic beginnt immer in Welle 1, hat keine Power-Ups, Bosse, Spezialbrocken, Timer oder Auto-Feuer und nutzt eine eigene Highscore-Liste. Moderner Sternenhimmel, HUD-Farben, Musikschalter und HDR-/EDR-Glow bleiben erhalten.

Als Verhaltensreferenzen dienten das [originale Bedienhandbuch](https://www.classicgaming.cc/classics/asteroids/files/tech-info/asteroids_manual.pdf) und der [wiederhergestellte Programm-Quelltext](https://github.com/historicalsource/asteroids/blob/main/A35131.1A). Atari-Grafiken, Samples, Logos, Koordinatentabellen oder Quellcode sind nicht enthalten.

## Power-Ups

Ancient und Mad enthalten neun Aufsammler mit jeweils eigenem Vektor-Symbol. Classic hat keine:

| Symbol | Power-Up | Wirkung |
|:--:|--|--|
| `S` | Schild | Energieschild fängt einen Treffer ab |
| `W` | Streuschuss | Dreifacher Fächer-Schuss |
| `R` | Schnellfeuer | Stark erhöhte Feuerrate |
| `O` | Option | Eine Satelliten-Drohne feuert mit |
| `B` | Bombe | Bildschirmräumende Explosion |
| `L` | Laserstrahl | Halten für einen sweependen, randumlaufenden Strahl |
| `T` | Heck | Zusätzlicher Schuss nach hinten |
| `C` | Kompress | Schrumpft das Schiff auf ~30 % (kleineres Ziel) |
| `+` | Extra-Leben | Wiederbelebung mittig mit kurzer Unverwundbarkeit |

## Gegner & Bosse

In Ancient und Mad füllt sich das Feld mit steigendem Level:

- **Gegnerische UFOs** — ein großes grünes UFO, das in zufällige Richtungen feuert, und ein kleines pinkes, das gezielt auf das Schiff schießt. Beide gleiten mit leichtem Sog in Richtung Spieler herein.
- **Gravitationsfelder** — Schwarze Löcher, die den Raum verzerren, alles nach innen ziehen und das Schiff bei Berührung zermalmen.
- **Implodierende Asteroiden** — magenta umrandete Brocken, die beim Abschuss zu einem frischen Gravitationsfeld kollabieren.
- **Wobble-Bomben** — rote Brocken, die pulsieren, in Stufen wachsen und dann in einen Fächer schneller Splitter detonieren.
- **Weltraumkatze** — ein pirschender Boss, der hinter Asteroiden in Deckung geht, deine Bewegung vorhält und mit Zwillings-Augenstrahlen feuert; drei Treffer vertreiben sie.
- **Das Idol** — ein großer schwebender Steinkopf, der hereingleitet, deinen Schüssen ausweicht und eine Armada UFOs aus dem Mund speit; zehn Treffer zerstören ihn.

## Steuerung

- **Startbildschirm:** ▲/▼ Spielmodus wechseln · ◀/▶ Ancient-/Mad-Startlevel wählen (Classic beginnt immer in Welle 1) · Leertaste/Enter starten · D (oder 30 s Leerlauf) eine Ancient-Autopilot-Demo ansehen · I Glossar · O Einstellungen · 1–5 ein Replay der zum gewählten Modus gehörenden Highscore-Liste ansehen
- **Ancient / Mad:** Pfeiltasten / WASD zum Fliegen · Leertaste zum Schießen (halten für Auto-Feuer / sweependen Strahl) · M Musik an/aus · G HDR-Glow an/aus · Esc Pause / Beenden
- **Classic:** Pfeiltasten / WASD zum Fliegen · Leertaste einmal je Schuss drücken · H Hyperspace · M Musik an/aus · G HDR-Glow an/aus · Esc Pause / Beenden
- **Einstellungen:** M Musik · N SFX-Stil · F Auto-Feuer · G HDR-Glow. Classic verwendet immer sein prozedurales Synth-Profil und deaktiviert Auto-Feuer; Musik und HDR bleiben unabhängig schaltbar. HDR-Glow ist standardmäßig aktiv, merkt sich die Auswahl und zeigt auf reinen SDR-Displays `UNAVAILABLE`.
- **Replay-Ansicht:** Esc verlässt das Replay zurück zum Startbildschirm.
- Highscores werden lokal gespeichert; bei einer Platzierung den Namen auf der Liste eintragen.
- **Cheat:** Taste `#` gibt ein Extra‑Leben — praktisch zum Testen oder für einen entspannten Durchlauf ohne Herausforderung.

## Replay & GIF-Export

Die Simulation ist **deterministisch**: Jeder Durchlauf wird allein als Seed plus deine Tastendrücke aufgezeichnet und lässt sich dadurch bit-genau reproduzieren. Daraus folgen zwei Dinge:

- **Highscore-Läufe erneut ansehen** — im Startbildschirm `1`–`5` drücken, um den Eintrag exakt so abzuspielen, wie er gespielt wurde; `Esc` verlässt ihn.
- **Promo-GIFs headless rendern** — ein Replay direkt auf der Kommandozeile in ein sauberes, cursorfreies animiertes GIF verwandeln, ganz ohne Fenster:

```bash
exploids --render-demo --out demo.gif            # skriptgesteuerter Demo-Lauf -> GIF (Pipeline-Selbsttest)
exploids --export-replay 0 --out run.replay      # Eintrag #0 der Standard-Liste (Default) exportieren
exploids --export-replay 0 --mode classic --out classic.replay
exploids --render-replay run.replay --out run.gif --scale 480 --fps 30
```

## Einordnung

Exploids ist ein Hobby-Klon, kein Produkt. Zur ehrlichen Einordnung, Schwachstellen ausdrücklich eingeschlossen:

**Gegenüber dem Original-Asteroids (1979)** — Classic Asteroids ist nun ein eigener arcadenaher Modus mit monochromen Umrissbrocken, zwei Untertassen, Hyperspace, Wellenwertung und Bonusschiffen, behält aber den modernen HDR-/EDR-Renderer und das deterministische Replay-System von Exploids. Ancient Asteroids und der rotierende Mad-Meteoroids-Modus bleiben das erweiterte, farbige Spiel mit neun Power-Ups, Gravitationsfeldern, Spezialbrocken, Bossen, sweependem Laserstrahl und Chiptune-Musik.

**Gegenüber Maelstrom** — [Maelstrom](https://github.com/libsdl-org/Maelstrom) (Ambrosia, 1992; seit 1995 GPL-SDL-Port, heute ein SDL2/SDL3-Build, der auf Apple Silicon läuft) ist der bekannteste noch gepflegte Open-Source-Asteroids-Klon für den Mac und der fairere Maßstab: Power-Ups, Bonus-Objekte und satten Sound hat er bereits. Worin sich Exploids tatsächlich unterscheidet:

- **Rendering:** Exploids ist prozedural gezeichnete Echtzeit-*Vektor*-Geometrie in hoher Auflösung und mit 120 Hz ProMotion samt HDR-/EDR-Neonglühen auf unterstützten Displays; Maelstrom ist Bitmap-/Sprite-Rastergrafik.
- **Audio:** Exploids synthetisiert die Soundeffekte live auf dem Audio-Thread (nur die zwei Musikstücke sind Dateien); Maelstrom spielt Samples ab.
- **Mechaniken:** der rotierende Mad-Meteoroids-Modus, Gravitationsfelder und imploding-Asteroiden sind Exploids-spezifisch.
- **Stack:** nativ Swift 6 / SpriteKit / AppKit auf Apple Silicon statt eines C/SDL-Ports.

**Wo Maelstrom klar vorn liegt:** Ein- *und* Mehrspieler (kooperativ und kompetitiv), Gamepad- und Touch-Steuerung, läuft auf mehr Plattformen und trägt 30 Jahre Feinschliff und Community. Exploids ist Einzelspieler, vorrangig Tastatur und macOS-Desktop (ein iOS-Touch-Target ist ein frühes Work in Progress) und jung. Außerdem bringt es nicht-kommerzielle Musik mit (siehe unten) — eine Einschränkung, die Maelstroms CC-lizenzierte Assets nicht haben.

## Lizenzen

- **Code:** [MIT](LICENSE) — © 2026 Daniel Müller.
- **Überschriften-Font** `Sources/GameCore/Fonts/PressStart2P-Regular.ttf` (Press Start 2P): **SIL Open Font License 1.1** (`Sources/GameCore/Fonts/OFL.txt`) — frei für jede Nutzung, auch kommerziell.
- **⚠️ Musik** `Sources/GameCore/Music/*.mp3` (zwei Chiptune-Stücke): erzeugt mit **[musely.ai](https://musely.ai)** im Free Plan — **nur persönliche, nicht-kommerzielle Nutzung**. Diese Stücke fallen **nicht** unter die MIT-Code-Lizenz und behalten die separaten Bedingungen von musely.ai. Vor jeder kommerziellen Nutzung durch eigene / CC0 / kommerziell lizenzierte Musik ersetzen. Alle anderen Klänge werden zur Laufzeit synthetisiert (keine Drittrechte).

## iOS-Target (Work in Progress)

Das Repo enthält außerdem ein iOS-App-Target unter `ios/` (SpriteKit + Touch-Steuerung auf dem Bildschirm), das dieselbe `GameCore`-Engine wie der macOS-Build einbindet. In Classic bleibt der linke Flug-Cluster unverändert; die rechte Spalte wird zu **HYPER** (Tippen), **THRUST** (Halten) und **FIRE** (Tippen). Ancient und Mad behalten ihre bisherige Steuerung. Das Target ist ein junges Work in Progress und noch nicht veröffentlicht.

## Voraussetzungen

macOS **14+**, Apple Silicon. Zum Bauen: eine vollständige Xcode-Installation (die Skripte nutzen `DEVELOPER_DIR=/Applications/Xcode.app/...` für die SpriteKit-/XCTest-Toolchain).

---

*Status: privates Projekt — eine prozedurale Vektor-Hommage an den Asteroids-Arcade-Klassiker von 1979, ohne übernommenen Code oder Assets.*
