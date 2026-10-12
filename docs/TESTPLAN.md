# Manueller Testplan für Roblox Studio

Die automatischen Tests (`tools/run_tests.sh`) prüfen Logik, Datenfluss und Laufzeitfehler in einer
Mock-Umgebung. Physik, Darstellung und Gerätebedienung lassen sich nur in Roblox Studio prüfen.
Dieser Plan führt in ca. 30–45 Minuten durch alle wichtigen Punkte.

Öffne während aller Tests das **Output-Fenster** (Ansicht → Ausgabe). Fehlermeldungen beginnen mit
`[ServiceName]` bzw. `[Controller]` und zeigen direkt die betroffene Datei.

---

## A. Solo-Test (Play, 1 Spieler)

| # | Schritt | Erwartung |
|---|---|---|
| A1 | Play drücken | Lobby mit Titel „VELOCITY RUSH“, drei Portale, Menü links, Statuskarte unten, TopBar oben links. Output: `[Velocity Rush] Server gestartet`. |
| A2 | A/D laufen, Leertaste springen | Figur läuft seitlich, beschleunigt/bremst weich, dreht sich in Laufrichtung, Laufanimation. Kamera folgt mit Vorausblick. |
| A3 | Leertaste kurz vs. lang | Kurzer Druck = niedriger Sprung, langer Druck = ca. 2 Körperhöhen. |
| A4 | Anlauf + Shift am Boden | Slide mit tiefer Pose, kurzer Schub; aufstehen beim Loslassen. |
| A5 | In der Luft Shift | Kurzer horizontaler Dash (einmal pro Sprung). |
| A6 | Rechts zur Wand am Spielplatz, an der Wand springen | Wall-Jump schleudert von der Wand weg; gegen die Wand drücken bremst den Fall. |
| A7 | Im Spielplatz E halten | Weißer Zielring am Anker, Seil sichtbar, Figur schwingt; loslassen = Abspringen mit Schwung. |
| A8 | In ein Portal stellen (TRAINING) | Nach ~1 s öffnet sich das Trainingsfenster. |
| A9 | Training → Bewegungs-Tutorial | Teleport ins Tutorial, Schilder erklären jede Station. Alle Stationen durchlaufen (Tunnel, Wall-Jump-Schacht, Greifhaken-Lücken, Dash-Lücke, Pads, Box + Q, Barriere). Ziel → Meldung mit Zeit, Neustart. |
| A10 | In eine Grube fallen / Barriere berühren | Respawn am letzten Checkpoint, kurz eingefroren. R = Checkpoint. |
| A11 | Training → Magma Works, dann „VERLASSEN“ | Trainingskopie wird gebaut, Verlassen bringt in die Lobby. |
| A12 | SCHNELLES SPIEL | Statuskarte: Warteschlange 1/8, „Rennen startet in 10 s“ (Solo-Modus nur in Studio). |
| A13 | Rennen | Beleuchtung wechselt zum Strecken-Theme, Countdown 3-2-1-LOS, Timer, Fortschrittsbalken, Platzierung, Item-Slot, Cooldowns. Ab 10 s „GEFAHRENZONE AKTIV IN …“, ab 18 s rote Wand. Ziel erreichen → „SIEG!“, Belohnungen, Siegesanimation. |
| A14 | Absichtlich zurückfallen | Roter Bildschirmrand + „ZURÜCK NACH VORNE!“; nach 1,6 s Ausscheiden, Explosion, Panel „AUSGESCHIEDEN“. |
| A15 | SHOP | 6 Kategorien, Vorschau dreht sich, Kauf mit zu wenig Coins → Fehlermeldung in Rot; Kauf mit genug Coins (z. B. Farbvariante 200) → Coins sinken, Item ausgerüstet und sofort an der Figur sichtbar. |
| A16 | INVENTAR, STATISTIK, BESTENLISTE, EINSTELLUNGEN | Fenster öffnen/schließen, Werte plausibel, Schieberegler und Schalter reagieren. |
| A17 | G drücken in der Lobby | Emote „Winken“ wird abgespielt. |
| A18 | M drücken | Menü klappt ein/aus. |

## B. Mehrspieler-Test (Test → Clients und Server, 3 Spieler)

| # | Schritt | Erwartung |
|---|---|---|
| B1 | Alle drei: SCHNELLES SPIEL | Warteschlange zählt 3, Countdown startet, alle drei auf der Strecke. |
| B2 | Rennen fahren | Andere Spieler laufen/animieren flüssig, Seile der anderen sichtbar, Namensschilder, Pfeile am Bildrand für Spieler außerhalb des Bildes. Spieler gehen durcheinander hindurch. |
| B3 | Items: Freeze Burst / Falle gegen andere | Ziel wird verlangsamt (Eisblock) bzw. betäubt (Sterne); mit Schild wird geblockt. |
| B4 | Ein Client schließt mitten im Rennen | Feed: „… hat das Spiel verlassen“; Rennen läuft weiter bzw. letzter Spieler gewinnt. |
| B5 | Ausgeschiedener Spieler: ZUSCHAUEN | Kamera folgt dem Führenden, ◀ ▶ wechselt, BEENDEN zurück. |
| B6 | Nach dem Ergebnis | Alle wieder in der Lobby, mit Auto-Requeue direkt wieder in der Warteschlange. |
| B7 | Zwei Spieler: RANKED | Ranked-Match, im Ergebnis Rating-Änderung, TopBar zeigt neuen Rang. |

## C. Geräte

| # | Schritt | Erwartung |
|---|---|---|
| C1 | Studio → Gerät emulieren: Smartphone (Querformat) | UI skaliert, Menü startet eingeklappt (MENÜ-Button), Touch-Buttons sichtbar, Item-Slot rechts oben. |
| C2 | Tablet | UI vollständig sichtbar, Fenster passen. |
| C3 | Gamepad (falls vorhanden) | Stick bewegt, A/X/B/Y funktionieren, Cooldown-Hinweise zeigen Gamepad-Tasten. Empfindlichkeit in den Einstellungen änderbar. |

## D. Speicherung (nach Veröffentlichung + API-Zugriff)

| # | Schritt | Erwartung |
|---|---|---|
| D1 | Rennen spielen, Item kaufen, Studio stoppen, erneut starten | Coins, XP, Level, Items, Einstellungen bleiben erhalten. |
| D2 | Bestenliste → Siege (global) | Eigener Eintrag nach einigen Minuten sichtbar. |

## E. Feintuning (falls nötig)

Alle Werte in `ReplicatedStorage/Shared/Config`:
- Laufgefühl: `Movement.MaxRunSpeed`, `GroundAcceleration`, `AirAcceleration`
- Sprung: `Movement.JumpVelocity`, `FallGravityMultiplier`, `World.Gravity`
- Greifhaken: `Grapple.Range`, `ReelSpeed`, `SwingAcceleration`, `ReleaseBoost`
- Gefahrenzone: `HazardZone.*`
- Kamera: `Camera.Distance`, `FieldOfView`, `LookAheadFactor`

Nach Änderungen an Sprungweite/-höhe `tools/run_tests.sh` ausführen bzw. die Strecken im Training prüfen.
