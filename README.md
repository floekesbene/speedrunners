# Velocity Rush – Multiplayer-Speed-Racing für Roblox

Ein vollständiges, eigenständiges Roblox-Spiel: schnelle 2D-Rennen in einer 3D-Welt für **bis zu 8 Spieler**,
mit eigener Bewegungsphysik, Greifhaken, Power-ups, einer schrumpfenden Gefahrenzone, 5 Strecken, Lobby,
Matchmaking, Ranked, Training, Shop, Inventar, Statistiken, Aufgaben und Bestenlisten.

Inspiriert vom Gameplay-Prinzip kompetitiver Side-Scrolling-Racer. Alle Namen, Strecken, Figuren, Skins,
Effekte und Oberflächen sind eigenständig. Es werden **keine externen Assets** benötigt: alles besteht aus
Roblox-Parts, Farben, Materialien, Partikeln und Roblox-eigenen Standard-Sounds.

> **Die komplette Spieldatei:** [`build/VelocityRush.rbxl`](build/VelocityRush.rbxl) – direkt in Roblox Studio öffnen.
> Zum Einfügen in einen bestehenden Place: [`build/VelocityRush_Import.rbxm`](build/VelocityRush_Import.rbxm).

---

## Inhalt

1. [Schnellstart](#1-schnellstart)
2. [Steuerung](#2-steuerung)
3. [Spielregeln](#3-spielregeln)
4. [Spielmodi](#4-spielmodi)
5. [Architektur](#5-architektur)
6. [Dateiliste](#6-dateiliste)
7. [Server-Client-Kommunikation](#7-server-client-kommunikation)
8. [Konfiguration](#8-konfiguration)
9. [Strecken und eigene Maps](#9-strecken-und-eigene-maps)
10. [Power-ups](#10-power-ups)
11. [Kosmetik, Shop und Fortschritt](#11-kosmetik-shop-und-fortschritt)
12. [Sicherheit und Anti-Exploit](#12-sicherheit-und-anti-exploit)
13. [Tests](#13-tests)
14. [Projektübersicht](#14-projektübersicht)
15. [Veröffentlichung](#15-veröffentlichung)
16. [Arbeiten mit Rojo (optional)](#16-arbeiten-mit-rojo-optional)

---

## 1. Schnellstart

Es gibt drei gleichwertige Dateien im Ordner `build/` – du brauchst nur **eine** davon.

| Datei | Wofür | So geht's |
|---|---|---|
| **`VelocityRush.rbxl`** (empfohlen) | komplettes Spiel als Place | Roblox Studio → *Datei → Öffnen* (bzw. Startseite → *Datei öffnen*) → Datei wählen → **Play** |
| `VelocityRush.rbxlx` | dasselbe als Text-Datei (XML) | wie oben |
| `VelocityRush_Import.rbxm` | in einen **bestehenden** Place importieren | siehe unten |

### Variante A – Place öffnen (am einfachsten)
1. `build/VelocityRush.rbxl` herunterladen (auf GitHub: Datei anklicken → *Download raw file*).
2. **Roblox Studio** öffnen → *Datei → Öffnen* → `VelocityRush.rbxl` wählen.
3. Oben auf **Play** (F5) klicken. Du startest in der Lobby.
   - In Studio darf ein Rennen auch **allein** starten (`Config.Debug.AllowSoloRace`), damit du sofort testen kannst.
   - Klicke **SCHNELLES SPIEL** → nach 10 s Countdown startet das Rennen.

### Variante B – in einen bestehenden Place importieren
1. Place in Roblox Studio öffnen (z. B. neue *Baseplate*).
2. Im **Explorer** mit Rechtsklick auf **Workspace** → *Aus Datei einfügen …* (Insert from File)
   → `VelocityRush_Import.rbxm` wählen. Es erscheint `Workspace/VelocityRush_Import`.
3. **Ansicht → Befehlsleiste** öffnen und diese Zeile einfügen und mit Enter ausführen:
   ```lua
   require(workspace.VelocityRush_Import.Install)()
   ```
   Der Installer verschiebt alles in die richtigen Services, setzt die Einstellungen
   (CharacterAutoLoads aus, Schwerkraft 200 …), entfernt Baseplate und SpawnLocation (sie liegen im
   Bereich der Rennstrecke) und löscht sich danach selbst. Im Output steht „Velocity Rush wurde installiert!“.
4. Falls der Output darum bittet: *Workspace* auswählen und im Eigenschaften-Fenster **StreamingEnabled**
   ausschalten (empfohlen; das Spiel funktioniert aber auch mit Streaming).
5. **Play** drücken.

Solange der Installer nicht ausgeführt wurde, ist das Server-Script im Modell deaktiviert – es kann also nichts
versehentlich am falschen Ort starten.

### Danach
- Für echte Mehrspieler-Tests: Reiter **Test → Clients und Server**, z. B. *2 Spieler* oder *3 Spieler*, **Start**.
- **Speichern aktivieren** (optional, für Coins/XP/Skins über Sitzungen hinweg):
  *Datei → In Roblox veröffentlichen*, danach *Spieleinstellungen → Sicherheit →
  „Studiozugriff auf API-Dienste aktivieren“*. Ohne diese Einstellung läuft das Spiel normal,
  speichert aber nicht (Hinweis im Spiel und in der Statistik).

Es müssen **keine** Instanzen manuell angelegt werden. Lobby, Strecken, Spielfigur, Remotes und die gesamte
Benutzeroberfläche werden beim Start per Script erzeugt. Deshalb ist der Workspace im Bearbeitungsmodus leer –
das ist normal. Alles erscheint, sobald du **Play** drückst.

---

## 2. Steuerung

Alle Eingaben laufen zentral über den `InputController`.

| Aktion | PC | Gamepad | Touch |
|---|---|---|---|
| Laufen | A / D oder ← / → | Linker Stick / D-Pad | ◀ ▶ |
| Springen (halten = höher) | Leertaste / W / ↑ | A | SPRUNG |
| Greifhaken (halten, loslassen = abspringen) | E / J / linke Maustaste | X oder R2 | HAKEN |
| Slide (Boden) / Air-Dash (Luft) | Shift / S / ↓ | B oder L2 | SLIDE |
| Power-up einsetzen | Q / F | Y oder R1 | ITEM |
| Emote | G | L1 | – |
| Respawn am Checkpoint | R | – (Esc-Menü → Zurücksetzen) | Esc-Menü |
| Menü ein/aus | M | Select | MENÜ-Button |

Weitere Techniken: **Wall-Jump** (in der Luft an einer Wand springen), **Wall-Slide** (gegen die Wand drücken),
**Kriechen** unter niedrigen Decken, **Coyote-Time** und **Sprungpuffer** für präzise Sprünge,
**Boost-Pads** und **Sprungpads**, rutschige **Eisflächen**.

---

## 3. Spielregeln

| Regel | Festlegung |
|---|---|
| Spieler | 2–8 pro Rennen (in Studio auch 1 zum Testen) |
| Start | Countdown 3-2-1-LOS, alle starten auf gleicher Höhe (gestaffelt nur in der Tiefe) |
| **Sieg** | a) Wer zuerst die **Ziellinie** überquert, gewinnt sofort. b) Ist nur noch **ein Spieler** übrig, gewinnt er. c) Nach **240 s** gewinnt der am weitesten Vorne. |
| **Gefahrenzone** | Energiewand, die dem Führenden folgt. Ab 10 s Warnung, ab 18 s gefährlich, Abstand schrumpft in 55 s von 260 auf 60 Studs. |
| **Ausscheiden** | Wer **1,6 s** hinter der Wand ist, scheidet aus. Die Gefahrenzeit baut sich in Sicherheit wieder ab. Der Führende ist nie in Gefahr. |
| Platzierung | Ausgeschiedene: Platz = Zahl der zu diesem Zeitpunkt noch aktiven Spieler. Übrige: Ziel zuerst, dann nach Fortschritt. |
| **Respawn** | Sturz in Abgrund oder Gefahr (Lava, Laser, Dornen, Eiswasser, Barrieren) → letzter Checkpoint, 0,9 s eingefroren. Checkpoints etwa alle 140 Studs. |
| Nach dem Ausscheiden | Kein Respawn im Rennen; zurück in die Lobby, Zuschauen möglich. |
| **Verlassen** | Zählt als Ausscheiden („Verlassen“), keine Belohnung, im Ranked als Letzter gewertet. Vor dem Start: fällt das Match unter 2 Spieler, wird es abgebrochen und die übrigen kommen zurück in die Warteschlange. |
| Nächste Runde | Nach 9 s Ergebnisanzeige zurück in die Lobby; mit „Automatisch erneut anstellen“ direkt wieder in die Warteschlange. |

Das Rundenende ist gegen doppelte Auslösung geschützt (`match.Ended`), ebenso die Belohnung (siehe Abschnitt 11).

---

## 4. Spielmodi

| Modus | Status | Beschreibung |
|---|---|---|
| **Quick Play** | implementiert | Warteschlange, Countdown, Rennen, Belohnungen, Auto-Requeue |
| **Practice** | implementiert | Bewegungs-Tutorial mit Schildern + jede Strecke als eigene Trainingskopie. Keine Zone, keine Belohnungen, keine Statistik. |
| **Ranked** | implementiert | Rangpunkte (Elo-artig, mehrspielerfähig), Matchmaking nach Rating innerhalb des Servers, Saisons, Leaver-Strafe, serverseitige Berechnung, keine Mehrfachwertung |
| Custom Matches | nicht implementiert | siehe Projektübersicht |

---

## 5. Architektur

### 5.1 Physik- und Bewegungsarchitektur

- **Einheitliche Spielfigur („RunnerRig“)**: Der Server legt beim Start ein R15-artiges Rig aus Parts als
  `StarterPlayer/StarterCharacter` an. Alle Spieler haben dadurch **identische Hitboxen**; Avatare und Skins
  können keinen Vorteil verschaffen.
- **Nur ein Kollider**: Ein unsichtbarer Quader `VR_Collider` (1,8 × 5,4 Studs, beim Sliden 2,2 Studs hoch) ist
  der einzige Teil, der mit der Welt kollidiert (Kollisionsgruppe `Runner`). Alle Körperteile und Kosmetik liegen
  in `RunnerBody` und kollidieren mit nichts. Spieler laufen durcheinander hindurch.
- **Humanoid deaktiviert**: `EvaluateStateMachine = false` bzw. Zustand `Physics`. Der Humanoid übt keine Kräfte aus.
- **Eigene Steuerung** (`MovementController`): In jedem Physikschritt (`RunService.PreSimulation`) wird die
  Geschwindigkeit gelesen, nach den Regeln (Beschleunigung, Momentum, Sprung, Slide, Dash, Seil …) verändert und
  zurückgeschrieben. **Schwerkraft und Kollisionen löst die Roblox-Engine** – Wände, Decken und Böden sind dadurch
  exakt und stabil. Eine `AlignOrientation` hält die Figur aufrecht und dreht sie nach links/rechts.
- **2D-Ebene**: Alle Bewegungen finden in X (Rennrichtung) und Y (Höhe) statt. Z wird jeden Schritt auf 0
  zurückgeführt; der Server korrigiert größere Abweichungen.
- **Greifhaken**: Das Seil ist eine eigene Distanzbedingung (einziehendes Seil: bei Durchhang wird es kürzer,
  bei Spannung wird die radiale Geschwindigkeit entfernt). Dadurch entsteht echtes Schwingen mit Momentum.
  Der Client simuliert sofort (keine Latenz), der Server validiert Ziel, Reichweite und Zustand.
- **Network Ownership**: Jeder Client simuliert seine eigene Figur (Roblox-Standard für Charaktere).
  Der Server ist autoritativ für Rundenzustand, Gefahren, Ziel, Zone, Items, Belohnungen und prüft die Bewegung.

### 5.2 Kamera

Scriptable-Seitenkamera (`CameraController`): Blick entlang −Z auf die Spielebene, leicht von oben, geglätteter
Look-Ahead in Laufrichtung, vertikale Totzone, schnelles Nachführen beim Fallen, Zoom und Sichtfeld wachsen mit
dem Tempo. Im Rennen verschiebt sich der Fokus leicht Richtung Führendem, damit er sichtbar bleibt.
Spieler außerhalb des Bildes werden durch **Pfeile am Bildschirmrand** mit Namen und Abstand angezeigt.
Zuschauermodus nach dem Ausscheiden. Die Gefahrenzone ist als rote Energiewand mit getönter Zone, als roter
Balken im Streckenfortschritt und als roter Bildschirmrand mit Countdown sichtbar.

### 5.3 Struktur in Roblox Studio

```
ReplicatedStorage
├── Shared/                 (gemeinsame Module, Server + Client)
│   Config, Remotes, Util, Signal, Progression, ItemDefinitions,
│   CosmeticDefinitions, MapDefinitions, QuestDefinitions,
│   RunnerRig, CosmeticApplier
├── Remotes/                (zur Laufzeit vom Server erzeugt)
└── GameState/              (zur Laufzeit: Rundenzustand als Attribute, Racers/<UserId>)

ServerScriptService
└── Server/
    ├── Bootstrap           (Script – Einstiegspunkt)
    ├── Modules/            MapBuilder, RateLimiter
    └── Services/           PlayerDataService, EconomyService, InventoryService, ShopService,
                            CharacterService, MapService, MatchmakingService, RoundService,
                            HazardRingService, GrappleService, PowerUpService, PracticeService,
                            RewardService, RankedService, LeaderboardService, AntiExploitService

ServerStorage
└── MapTemplates/           _Template, Lobby, Tutorial, NeonMetropolis, MagmaWorks,
                            SkywayRuins, GlacierCircuit, JungleVelocity

StarterPlayer
├── StarterCharacter        (zur Laufzeit vom Server erzeugt)
├── StarterPlayerScripts/Client/
│   ├── Main                (LocalScript – Einstiegspunkt)
│   ├── Controllers/        ClientState, InputController, MovementController, CameraController,
│   │                       AnimationController, EffectsController, AudioController
│   └── UI/                 UIController, Theme, Components,
│       └── Screens/        TopBar, LobbyMenu, RaceHud, Results, Catalog (Shop+Inventar),
│                           Stats, Leaderboard, Settings, Practice, TouchControls, Notifications
└── StarterCharacterScripts/
    └── Animate             (LocalScript, absichtlich leer – ersetzt Roblox-Standardanimationen)

Workspace (zur Laufzeit)
├── Lobby, ActiveMap, Practice   (gebaute Regionen)
└── VR_ClientFX                  (nur lokal: Effekte)
```

**Abweichungen von der Vorgabe-Struktur (bewusst):**
- Die UI wird komplett per Code in `PlayerGui/VelocityRushUI` erzeugt (statt einzelner ScreenGuis in StarterGui).
  Vorteil: keine manuellen Instanzen, einheitliches Designsystem, eine Skalierung für alle Geräte.
  Die geforderten Bereiche MainUI/LobbyUI/RaceUI/ShopUI/InventoryUI/ResultsUI entsprechen den Screens
  `LobbyMenu`, `RaceHud`, `Catalog` (Shop + Inventar), `Results` usw.
- `SkinDefinitions` heißt `CosmeticDefinitions` (enthält Skins, Trails, Effekte, Emotes, Siegesanimationen, Farben).
- `ServerStorage/ItemTemplates` und `CosmeticTemplates` sind nicht nötig, da Items und Kosmetik vollständig aus
  Definitionen per Code gebaut werden.
- Zusätzliche Services: `CharacterService`, `PracticeService`, `RewardService`, `RankedService`.

### 5.4 Ablauf eines Rennens (Server)

```
Waiting ─(≥2 in Warteschlange)→ Starting (10 s, bei 8 Spielern 4 s)
        → Loading (Map bauen, Spieler an Spawns, eingefroren)
        → Countdown (3,5 s) → Racing (10-Hz-Tick: Fortschritt, Checkpoints, Gefahren,
          Ziel, Zone, Platzierung) → Results (9 s, Belohnungen) → Aufräumen → Waiting
```

---

## 6. Dateiliste

Alle Pfade beziehen sich auf Roblox Studio. Der Quelltext liegt im Repository unter `src/` mit gleicher Struktur.
**Installation:** Alles ist bereits in `build/VelocityRush.rbxlx` enthalten – nichts muss einzeln eingefügt werden.

### Gemeinsam (ReplicatedStorage/Shared) – ModuleScripts

| Datei | Zweck | Abhängigkeiten |
|---|---|---|
| `Config` | Alle Balancing-Werte (Movement, Greifhaken, Zone, Runde, Ökonomie, Ranked, Anti-Exploit, Kamera, Audio) | – |
| `Remotes` | Erzeugt (Server) bzw. findet (Client) alle RemoteEvents/-Functions | – |
| `Util` | Mathe-, Tabellen- und Formatierungshilfen | – |
| `Signal` | Leichtgewichtige Events zwischen Modulen | – |
| `Progression` | Levelkurve, Ranked-Stufen, Elo-Berechnung | – |
| `ItemDefinitions` | 6 Power-ups mit Werten und Spawn-Gewichtung | – |
| `CosmeticDefinitions` | 13 Skins, 6 Trails, 5 Effekte, 5 Emotes, 4 Siegesanimationen, 6 Farbvarianten, Seltenheiten | – |
| `MapDefinitions` | Namen, Beschreibungen, Schwierigkeit und Themes (Beleuchtung) aller Strecken | – |
| `QuestDefinitions` | Tagesaufgaben und Erfolge | – |
| `RunnerRig` | Baut die einheitliche Spielfigur (Parts + Motor6D + Kollider) | Config |
| `CosmeticApplier` | Wendet Skin/Farbe/Trail/Effekt auf ein Rig an | CosmeticDefinitions |

### Server (ServerScriptService/Server)

| Datei | Typ | Zweck | Abhängigkeiten |
|---|---|---|---|
| `Bootstrap` | Script | Kollisionsgruppen, Services laden/starten, 10-Hz-Tick, geordnetes Aufräumen | alle Services |
| `Modules/MapBuilder` | ModuleScript | Strecken-Baukasten (Bausteine, Dekoration, Checkpoints) | Config |
| `Modules/RateLimiter` | ModuleScript | Token-Bucket pro Spieler und Remote | Config |
| `Services/PlayerDataService` | ModuleScript | DataStore-Profile, Session-Lock, Autosave, BindToClose, Einstellungen | Config, Util, Remotes |
| `Services/EconomyService` | ModuleScript | Coins/XP/Level, leaderstats | PlayerDataService |
| `Services/InventoryService` | ModuleScript | Besitz, Ausrüsten, Ablegen | PlayerDataService, CharacterService |
| `Services/ShopService` | ModuleScript | Kaufen/Ausrüsten mit Validierung | Economy, Inventory |
| `Services/CharacterService` | ModuleScript | Spawnen, Teleports, Kosmetik, Namensschilder, MoveState, Emotes, Lobby-Portale | Round, Practice, Map |
| `Services/MapService` | ModuleScript | Regionen bauen/entladen, Rotation, Gefahrenprüfung | MapBuilder, Grapple, PowerUp |
| `Services/MatchmakingService` | ModuleScript | Warteschlangen Quick Play/Ranked, Auswahl nach Rating | PlayerData, Round |
| `Services/RoundService` | ModuleScript | Rundenablauf, Renn-Tick, Platzierung, Ende | fast alle |
| `Services/HazardRingService` | ModuleScript | Gefahrenzone (Timing, Position, Ausscheiden) | Config |
| `Services/GrappleService` | ModuleScript | Anker-Registry, Greifhaken-Validierung | Character, Reward |
| `Services/PowerUpService` | ModuleScript | Item-Boxen, Benutzen, Effekte, Fallen | Round, Character, Map |
| `Services/PracticeService` | ModuleScript | Trainingsmodus | Map, Character |
| `Services/RewardService` | ModuleScript | Match-Belohnungen, Statistiken, Aufgaben, Erfolge | Economy, Inventory |
| `Services/RankedService` | ModuleScript | Rating, Saisons, Leaver-Strafe | Progression |
| `Services/LeaderboardService` | ModuleScript | OrderedDataStores, Cache, Serverliste | PlayerData |
| `Services/AntiExploitService` | ModuleScript | Geschwindigkeits-/Ebenen-/Einfrier-Prüfung | Character |

### Strecken (ServerStorage/MapTemplates) – ModuleScripts

`_Template` (Vorlage), `Lobby`, `Tutorial`, `NeonMetropolis`, `MagmaWorks`, `SkywayRuins`, `GlacierCircuit`, `JungleVelocity`.

### Client (StarterPlayer)

| Datei | Typ | Zweck |
|---|---|---|
| `StarterPlayerScripts/Client/Main` | LocalScript | Einstiegspunkt, Standardsteuerung aus |
| `Controllers/ClientState` | ModuleScript | Profil, GameState, Server-Events |
| `Controllers/InputController` | ModuleScript | Tastatur, Maus, Gamepad, Touch |
| `Controllers/MovementController` | ModuleScript | Eigene Bewegungsphysik + Greifhaken |
| `Controllers/CameraController` | ModuleScript | Seitenkamera, Zuschauen, Wackeln |
| `Controllers/AnimationController` | ModuleScript | Prozedurale Animationen aller Figuren |
| `Controllers/EffectsController` | ModuleScript | Licht, Seile, Zone, Status- und Einmal-Effekte |
| `Controllers/AudioController` | ModuleScript | Sounds und Lautstärken |
| `UI/UIController`, `UI/Theme`, `UI/Components` | ModuleScripts | UI-Gerüst, Designsystem, Bausteine |
| `UI/Screens/*` | ModuleScripts | TopBar, LobbyMenu, RaceHud, Results, Catalog, Stats, Leaderboard, Settings, Practice, TouchControls, Notifications |
| `StarterCharacterScripts/Animate` | LocalScript | Leer – deaktiviert Roblox-Standardanimationen |

---

## 7. Server-Client-Kommunikation

### Remotes (`ReplicatedStorage/Remotes`)

| Name | Art | Richtung | Argumente | Validierung |
|---|---|---|---|---|
| QueueRequest | Event | C→S | `"Join"/"Leave"`, `"QuickPlay"/"Ranked"` | Modus, Profil geladen, nicht im Rennen |
| PracticeRequest | Event | C→S | `"Enter"/"Leave"/"Reset"`, courseId | Strecke existiert, nicht im Rennen |
| MoveState | Event | C→S | Zustand, Blickrichtung | Whitelist, Rate-Limit |
| GrappleRequest | Event | C→S | `"Attach"`, anchorId / `"Release"` | Region, Reichweite, Zustand, Intervall |
| UsePowerUp | Event | C→S | – | Item vorhanden, Debounce, Zustand, Region |
| PlayEmote | Event | C→S | – | Besitz, nicht während des Rennens |
| SaveSettings | Event | C→S | Einstellungstabelle | Typen und Wertebereiche |
| RequestRespawn | Event | C→S | – | Rate-Limit |
| GameEvent | Event | S→C | Name, Payload | – |
| ProfileUpdate | Event | S→C | Profil-Schnappschuss | – |
| GetProfile | Function | C→S | – | Rate-Limit |
| ShopRequest | Function | C→S | `"Buy"/"Equip"/"Unequip"`, Kategorie, Id | vollständige Kauf-/Besitzprüfung |
| GetLeaderboard | Function | C→S | – | Rate-Limit, Cache |

Alle Remotes sind per Token-Bucket begrenzt (`Config.RateLimits`).

### Replizierter Zustand (Attribute)
- `ReplicatedStorage/GameState`: Phase, PhaseEndsAt, MatchId, Mode, MapId, NextMapId, Warteschlangen, Teilnehmer,
  Alive, StartX/FinishX, Checkpoints, Zone (State, X, Länge, Zeiten).
- `GameState/Racers/<UserId>`: Name, Status, Placement, Progress, DangerTime, Checkpoint, Respawns.
- Player: Queue, InRace, PracticeCourse, HeldItem, Level, Rating, Tier.
- Spielfigur: MoveState, Facing, Frozen, Grappling, GrappleTarget, Status-Ablaufzeiten (Boost, Schild, Freeze,
  Betäubung, Haken-Upgrade), Emote, Victory, AccentColor.

---

## 8. Konfiguration

Alle Werte stehen in `ReplicatedStorage/Shared/Config` und gelten für Server und Client. Wichtige Abschnitte:

| Abschnitt | Beispiele |
|---|---|
| `Movement` | MaxRunSpeed 44, JumpVelocity 62 (≈ 9,6 Studs Sprunghöhe), Slide, Dash, Wall-Jump, Eis |
| `Grapple` | Reichweite 58, Einziehgeschwindigkeit, Cooldown, Server-Toleranz |
| `HazardZone` | Warnung/Start/Dauer, Anfangs- und Endabstand, Ausscheide-Verzögerung |
| `Round` | Min./Max. Spieler, Countdown, Renndauer, Ergebnisdauer |
| `Rewards`, `Economy` | Coins/XP für Teilnahme und Platzierungen, Level-Up-Bonus |
| `Ranked` | Saison, Startwert, K-Faktor |
| `AntiExploit` | Messfenster, Grenzgeschwindigkeit, Kick-Schwelle |
| `Camera`, `Audio`, `RateLimits`, `Debug` | … |

`Config.Debug.AllowSoloRace` ist nur in Studio aktiv (Rennen mit 1 Spieler).

---

## 9. Strecken und eigene Maps

| Strecke | Theme | Schwierigkeit | Besonderheiten |
|---|---|---|---|
| Neon Metropolis | Futuristische Stadt bei Nacht | ★★ | Laserbarrieren, Dächer-/Tunnelroute, tödlicher Lasertunnel |
| Magma Works | Industrieanlage über Lava | ★★★ | Lavagruben mit Säulen, Flammenwerfer, Sprungpads |
| Skyway Ruins | Schwebende Ruinen über Wolken | ★★ | viele Greifhaken-Passagen, Abgründe |
| Glacier Circuit | Eis und Schnee | ★★ | rutschige Eisflächen, Eiszapfen-Tunnel |
| Jungle Velocity | Dschungel | ★ | zwei geteilte Abschnitte (Baumkronen / Waldboden) |

Jede Strecke hat Startbereich mit 8 Spawnpunkten, Plattformen, Hindernisse, geteilte Routen (oben schnell und
schwer, unten sicherer – wer oben scheitert, fällt in die untere Route), Greifhaken-Anker, Item-Spawns,
Gefahrenbereiche, automatische Checkpoints, Ziellinie, eigenes Theme mit Beleuchtung und Hintergrund.

**Eigene Map hinzufügen:**
1. `ServerStorage/MapTemplates/_Template` duplizieren und umbenennen.
2. In `ReplicatedStorage/Shared/MapDefinitions` einen Eintrag (Id, Name, Template, Difficulty, Seed, Theme) anlegen
   und die Id in `MapDefinitions.Order` eintragen.
3. Die Strecke mit Bausteinen beschreiben (`Flat`, `Gap`, `Steps`, `SlideTunnel`, `WallClimb`, `GrappleGap`,
   `Pit`, `TimedBarrier`, `BoostStrip`, `IceRun`, `PickupRow`, `Split`, `Finish` …, siehe `MapBuilder`).
4. `tools/run_tests.sh` prüft automatisch, ob jede Lücke überwindbar ist.

---

## 10. Power-ups

| Item | Wirkung | Fairness |
|---|---|---|
| Speed Boost | +35 % Höchstgeschwindigkeit für 3 s, kurzer Schub | – |
| Shield | blockt den nächsten Freeze/Falle (6 s) | – |
| Freeze Burst | verlangsamt Gegner im Radius 45 für 1,8 s | Schild blockt |
| Grapple Upgrade | 8 s: Reichweite ×1,6, schneller einziehen, kein Cooldown | – |
| Teleport Beacon | zum nächsten sicheren Punkt bis 48 Studs voraus | nie über die Ziellinie; ohne Ziel nicht verbraucht |
| Trap | sichtbare Falle (15 s), betäubt Gegner 1,2 s | sichtbar, Besitzer immun, max. 1 pro Spieler |

Ein Item pro Spieler. Verteilung nach Rennposition (Führende bekommen seltener starke Angriffs-Items).
Kein Pay-to-Win: Items gibt es nur im Spiel aus Boxen.

---

## 11. Kosmetik, Shop und Fortschritt

- **Kategorien:** 13 Skins, 6 Trails, 5 Partikeleffekte, 5 Emotes, 4 Siegesanimationen, 6 Farbvarianten.
- **Seltenheiten:** Gewöhnlich, Selten, Episch, Legendär. Ein Skin erfordert Level 20.
- **Shop/Inventar:** 3D-Vorschau (Emotes und Siegerpose animiert), Kaufen, Ausrüsten, Ablegen,
  verständliche Fehlermeldungen („Nicht genug Coins – dir fehlen 200“).
- Kosmetik ist rein visuell (Massless, keine Kollision, kein Einfluss auf Tempo oder Sprung).
- **Belohnungen** (nur serverseitig): Teilnahme 20 Coins/35 XP, Platz 1–3 +60/35/20 Coins und +100/60/40 XP
  (skaliert mit Spielerzahl), Ziel erreicht +15/25, Level-Up-Bonus, 3 Tagesaufgaben, 10 Erfolge.
- **Statistiken:** Rennen, Siege, Top 3, Ziel erreicht, Ausgeschieden, Greifhaken, Power-ups, Distanz,
  Bestzeiten pro Strecke, Ranked-Saison.
- **Schutz vor Mehrfachbelohnung:** pro Match im Speicher (`match.Rewarded`), persistent über die letzten
  25 Match-IDs im Profil, Aufgaben/Erfolge mit Erledigt-Status.
- **Speicherung:** DataStoreService mit UpdateAsync, Session-Lock, Wiederholungen, Autosave alle 90 s,
  Speichern beim Verlassen und Herunterfahren.

---

## 12. Sicherheit und Anti-Exploit

- Server autoritativ für Rundenzustand, Gefahren, Ziel, Zone, Platzierung, Items, Coins, XP, Rating, Käufe.
- Rate-Limits auf allen Remotes, Typprüfung aller Argumente.
- Bewegung: Geschwindigkeitsprüfung über 1-s-Fenster (Grenze 230 Studs/s, legitimes Maximum ≈ 195),
  Rückversetzung statt sofortigem Kick; Kick erst nach wiederholten groben Verstößen (abschaltbar).
  Spielebene (Z) wird erzwungen, eingefrorene Spieler dürfen sich nicht bewegen.
- Greifhaken: nur registrierte Anker der eigenen Region, Reichweite + Toleranz, Mindestintervall.
- Items: Besitz, Debounce, Entfernen vor Wirkung (keine Doppelnutzung).
- Käufe: Preise nur aus Server-Definitionen, keine Doppelkäufe, atomare Abbuchung, Sperre pro Spieler.
- Verlassen/Verbindungsabbruch, Respawn, gleichzeitige Rundenenden: alle Fälle sind im `RoundService` geregelt.

---

## 13. Tests

### 13.1 Automatisierte Tests (bereits ausgeführt)

`tools/run_tests.sh` führt aus:
1. **Syntaxprüfung** aller 61 Luau-Dateien mit dem echten Luau-Compiler.
2. **Selene-Linter** (undefinierte Variablen, unbenutzte Werte …).
3. **Querverweis-Prüfung**: Jeder Aufruf zwischen Services/Controllern zeigt auf eine existierende Methode.
4. **Strecken-Prüfung** (`tools/test/maps_test.luau`): baut alle 7 Regionen, prüft Spawnpunkte, Ziel, Checkpoints
   auf festem Boden, KillY, und dass jede Bodenlücke > 25 Studs Greifhaken-Anker hat.
5. **End-to-End-Simulation** (`tools/test/server_test.luau`) in einer Mock-Roblox-Umgebung
   (`tools/test/mock.luau`): Server (Bootstrap + alle Services) **und** kompletter Client inklusive UI laufen
   gemeinsam; simulierte Spieler treten bei, kaufen ein, trainieren, spielen Quick-Play- und Ranked-Rennen,
   verlassen mitten im Rennen, der Server fährt herunter. **Ergebnis: 75 von 75 Prüfungen bestanden,
   0 Laufzeitfehler.**
6. **Streaming-Variante**: dieselbe Simulation mit `StreamingEnabled = true` (Absicherung für importierte Places).
7. **Import-Test** (`tools/test/import_test.luau`): frischer Place mit Baseplate → Modell einfügen → Installer
   ausführen → Struktur und Einstellungen prüfen → Spiel starten, Spieler beitreten, Solo-Rennen startet.
   **17 von 17 Prüfungen bestanden.**
8. **Build** von `VelocityRush.rbxl`, `VelocityRush.rbxlx` und `VelocityRush_Import.rbxm` mit Rojo.

Voraussetzungen zum erneuten Ausführen: Rust (`cargo`), Python 3, `cargo install rojo selene`.

**Was die Simulation nicht abdeckt:** echte Roblox-Physik und Kollisionen, Darstellung, UI-Layout auf echten
Geräten, Netzwerk-Latenz, echte DataStore-Limits. Dafür siehe den manuellen Testplan:
[`docs/TESTPLAN.md`](docs/TESTPLAN.md).

---

## 14. Projektübersicht

### Vollständig implementiert und automatisiert getestet (Mock-Simulation)
- Rundenablauf Quick Play: Warteschlange, Countdown, Rennen, Ausscheiden, Sieg (Ziel / letzter Spieler / Zeit),
  Ergebnis, Auto-Requeue, Abbruch bei zu wenigen Spielern, Verlassen während des Rennens
- Gefahrenzone (Timing, Position, Ausscheiden), Respawn an Checkpoints, Gefahrenprüfung entlang der Bewegung
- Ranked: Matchmaking nach Rating, Elo-Wertung, Saison, Leaver-Strafe
- Belohnungen, Level, Statistiken, Bestzeiten, Tagesaufgaben, Erfolge, Schutz vor Doppelbelohnung
- Profile mit DataStore (Session-Lock, Speichern beim Verlassen/Herunterfahren), Studio-Fallback
- Shop/Inventar-Server: Kauf, Doppelkauf-Schutz, Ausrüsten, Ablegen, Fehlermeldungen, manipulierte Anfragen
- Training: Tutorial und Trainingskopien aller Strecken, Respawn, Verlassen
- Power-up-Server: Boxen, Zufallsauswahl, Einsatz, Effekte; Greifhaken-Validierung inkl. Ablehnung
- Map-System: 5 Strecken + Lobby + Tutorial, Rotation, Laden/Zurücksetzen/Entladen, Spielbarkeitsprüfung
- Client-Code (Controller + UI) läuft in der Simulation ohne Laufzeitfehler durch alle Phasen

### Implementiert, aber noch in Roblox Studio zu testen
- **Bewegungsgefühl** mit echter Roblox-Physik (Kollider, Sprungweiten, Wall-Jump, Slide-Tunnel, Seilschwung,
  Rampen) – Feintuning über `Config.Movement`/`Config.Grapple`
- Kamera, prozedurale Animationen, visuelle Effekte, Beleuchtungs-Themes
- UI-Layout und Lesbarkeit auf PC, Tablet und Smartphone; Touch- und Gamepad-Steuerung
- Shop-Vorschau im ViewportFrame
- Live-DataStores und globale Bestenlisten (nach Veröffentlichung)
- Mehrspieler mit echter Netzwerklatenz (Test → Clients und Server)
- Sounds: es werden nur Roblox-eigene `rbxasset://sounds/...` verwendet (eigene IDs in `Config.Audio` möglich)

### Noch nicht implementiert
- Serverübergreifendes Matchmaking (MemoryStoreService + TeleportService) – bewusst nach Vorgabe erst,
  wenn das Matchmaking im Server zuverlässig läuft
- Custom Matches (private Lobbys, eigene Regeln, Einladungen)
- Hintergrundmusik (nur Schalter vorhanden; benötigt eine eigene Audio-ID in `Config.Audio.MusicId`)
- Animationen als Roblox-Animation-Assets (aktuell prozedural, funktioniert ohne Assets)
- Monetarisierung (bewusst keine; kein Pay-to-Win)

---

## 15. Veröffentlichung

Checkliste:
- [ ] Place in Studio öffnen, **Play** und **Test → 3 Spieler** durchspielen (siehe `docs/TESTPLAN.md`)
- [ ] *Datei → In Roblox veröffentlichen*
- [ ] *Spieleinstellungen → Sicherheit*: „Studiozugriff auf API-Dienste“ für Tests aktivieren
- [ ] *Spieleinstellungen → Avatar*: egal (Velocity Rush nutzt eine eigene Spielfigur)
- [ ] *Spieleinstellungen → Orte*: Maximale Spielerzahl z. B. **16** (zwei Rennen nacheinander, Lobby-Puffer)
- [ ] `Config.Debug.AllowSoloRace` ist nur in Studio aktiv – nichts zu tun
- [ ] Optional: `Config.AntiExploit.KickEnabled` prüfen
- [ ] Optional: eigene Sound-/Musik-IDs in `Config.Audio` eintragen
- [ ] Spielsymbol, Thumbnails und Beschreibung hochladen; Erfahrungsfragebogen (Altersfreigabe) ausfüllen
- [ ] Öffentlich schalten, ersten Live-Test mit mehreren Personen machen, Output/Developer Console prüfen

---

## 16. Arbeiten mit Rojo (optional)

Der Quelltext liegt unter `src/` und ist ein [Rojo](https://rojo.space)-Projekt (`default.project.json`).

```bash
cargo install rojo                     # oder per Aftman/Rokit
rojo build default.project.json -o build/VelocityRush.rbxl          # Place-Datei bauen
rojo build import.project.json -o build/VelocityRush_Import.rbxm    # Import-Modell bauen
rojo serve                             # Live-Sync mit dem Rojo-Studio-Plugin
./tools/run_tests.sh                   # alle Prüfungen + Build
```
