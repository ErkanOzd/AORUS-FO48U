---
paths:
  - "Sources/MonitorDeck/**"
---

# UX-Leitlinien MonitorDeck

Allgemeine Leitlinien: `~/.claude/rules/ux.md`. Hier nur die Umsetzung in MonitorDeck; neue Funktionen werden vor „fertig“ gegen beide Dateien geprüft.

- Live-Werte: Oberflächen melden sich über `Model.watch` mit den Werten an, die sie zeigen; Sichtbarkeit liefert `WindowVisibility` (Occlusion-Status). Ohne sichtbare Oberfläche pollt die App nicht (es lesen dann nur Tastendrücke und, falls eingeschaltet, das Dashboard). Antwortet ein Durchlauf gar nicht, gilt der Monitor als getrennt (`Worker.reset`).
- Eigene Änderungen sofort spiegeln: Tastendrücke schreiben ihren Wert über `Model.external` direkt ins Menü (erst erwartet, dann bestätigt); gelesene Menüwerte dienen über `KeyJobs.remember` als Ausgangswert für das OSD.
- Vorrang der Eingabe: `Model.dragging` (laufender Ziehvorgang) und `epoch` (geschriebener Wert) sperren Lesewerte; gelesen wird je Wert als eigener Auftrag auf der DDC-Queue, nie auf dem Main-Thread.
- Rückmeldung: angezeigt wird der vom Monitor zurückgelesene Wert (`WriteResult`), Abweichungen als Hinweis im Menü.
- Bestätigung: Eingangswechsel weg von USB-C nimmt dem Mac das Bild und wird vorher abgefragt.
- Texte zweisprachig über `tr(de, en)`.
