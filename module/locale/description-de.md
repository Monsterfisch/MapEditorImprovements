# Map Editor Improvements

**Autoren**: Monsterfish, Heroesflorian
**Version**: 1.0.65

Zeigt im Karteneditor deutlich mehr Informationen über die bearbeitete Karte an und ergänzt Werkzeuge, die dem Editor fehlen: Wachstumsstufen für Bäume, Apfelbäume, mehr Sträucher, gefällte Bäume, Kies und Eisen, Felsenvarianten, Herdengrößen und vieles mehr. Jeder Teil lässt sich in den Einstellungen einzeln abschalten.

## Kartenzähler

Im Landschaftseditor:

- **Hinweise auf den Kategorieschaltflächen.** Zeige mit der Maus auf eine Schaltfläche, um die aktuelle Anzahl im Vergleich zum Spiellimit zu sehen:
  - **Tiere:** Tiere und Einheiten gegen das echte Limit (2499, 9999 in Extreme), Herden und Gruppen – jede platzierte Herde und jede Truppengruppe belegt einen Platz mit eigenem Limit (1249) – sowie Vögel: Krähen (Markierungen an Bäumen, ohne eigenes Limit) und Möwen (höchstens 99).
  - **Vegetation:** Bäume und Sträucher. Alle Pflanzen teilen sich ein gemeinsames Limit von 1999.
  - **Felsen:** Felsen.
- **Tiere-Menü:** Die Schaltflächen für Hirsche, Kamele, Hasen und Löwen zeigen jeweils die Anzahl auf der Karte.
- **Vegetationsmenü:** Jede Baum- und Strauch-Schaltfläche zeigt die Anzahl der jeweiligen Pflanze auf der Karte.

Über der Schlüssel-Schaltfläche sitzt eine rote **„i“**-Schaltfläche. Klicke darauf, um alle Zahlen auszublenden, und erneut zum Einblenden. Die Einstellungen bestimmen, ob sie beim Öffnen angezeigt werden. Die Beschreibungszeile der Schaltflächen rückt dafür etwas nach rechts.

## Bäume und Sträucher

Die Bäume im Vegetationsmenü sind danach geordnet, auf welchem Boden sie sich ausbreiten: zuerst die drei Bäume für fruchtbaren Boden (Oasengras, dichtes und dünnes Gestrüpp) mit dünnem grünen Rahmen, dann der Baum für unfruchtbaren Boden (Erde, steinige Erde, Dünen) mit dünnem beigen Rahmen.

- **Wachstumsstufe über die Pinselgröße.** Ist ein Baum gewählt, legt die Pinselgröße seine Größe fest:

  | Pinsel | Baum |
  |---|---|
  | 1 bis 3 | junge Bäume, kleinster zuerst |
  | 4 | ausgewachsen (Standard des Editors) |
  | 5 | ausgewachsen; Holzfäller lassen ihn in Ruhe, bis er wieder zu einem normalen Baum wird |
  | 6 | abgestorbener Baum |
  | 7 | abgestorbener Baum, der schneller verschwindet |

  Sträucher bleiben stets gleich.
- **Apfelbaum-Schaltfläche** im Vegetationsmenü (auf der Beschreibungszeile wie andere Pflanzen benannt: „Apfelbaum“, auf Englisch „Apple tree“).
- **Mehr Sträucher.** Ist der Strauch mit fünf Farben gewählt, bietet eine Leiste über dem Vegetationsmenü alle fünf Farben an.
- **Gefällte Bäume.** Ist ein Baum gewählt, zeigt eine Leiste über dem Vegetationsmenü ihn zuerst stehend und dann gefällt für jede mögliche Stammanzahl: 9 bis 1 bei ausgewachsenen Bäumen, weniger bei kleineren, keine bei abgestorbenen (die kleinsten Bäume liegen mit 1 Stamm als Baum der nächsten Stufe). Klicke einen an, um gefällte Bäume mit so vielen Stämmen zu setzen; ein weiterer Klick darauf, auf den stehenden Baum oder auf den Baum im Menü setzt wieder stehende Bäume.
- **Zufällige Mischungen.** Die Leisten über dem Vegetationsmenü erhalten Schaltflächen mit „?“:
  - **Zufälliger Baum**, zuerst in der Leiste gefällter Bäume: jeder gesetzte Baum erhält eine zufällige Wachstumsstufe von der kleinsten bis zur Pinselstufe (nicht bei Pinsel 1 oder abgestorbenen Bäumen).
  - **Zufälliger gefällter Baum**, zuletzt in der Leiste gefällter Bäume: gefällte Bäume mit zufälliger Stammanzahl von 1 bis zum Maximum dieses Baums.
  - **Zufälliger Strauch**, zuletzt in der Strauchleiste: zufällige Mischung der fünf Strauchfarben.

  Erneut klicken oder eine andere Schaltfläche wählen beendet das Mischen.
- **Bäume neben Hindernissen.** Ein Kontrollkästchen am Ende der oberen Reihe. Angehakt lassen sich Bäume direkt neben Gebäuden, Felsen, Mauern und anderen Bäumen setzen (Sträucher können dort ohnehin stehen). Zeige darauf, um den Zustand zu sehen.
- **Geordnete Reihen.** Oben stehen die Bäume (samt Apfelbaum und Kontrollkästchen); der frühere Strauch dort wandert in die sortierte untere Strauchreihe.
- **Baumvorschau.** Ist ein Baum oder Strauch gewählt, erscheint er auf dem Feld unter dem Mauszeiger in der jeweiligen Wachstumsstufe oder gefällt mit der gewählten Stammzahl – auch bei der Pipette. Nicht im herausgezoomten Zustand und nicht an unzulässigen Stellen; auch bei ausgeblendetem Menü (Tab) sichtbar.
- **Keine gestapelten Sträucher.** Ein Baum oder Strauch kann nicht mehr auf ein bereits belegtes Feld gesetzt werden. Manche Sträucher stapelten sich sonst unsichtbar auf demselben Feld und verbrauchten dauerhaft Baumlimit; der Radierer entfernt nun auch alle gestapelten Sträucher eines Felds.

Die Leiste über dem Vegetationsmenü liegt über der Karte; Klicks darauf setzen nichts auf der Karte ab.

## Bodentexturen

Das Texturenmenü erhält **Kies** am Ende der oberen Reihe und **Eisen** am Ende der unteren Reihe (dasselbe Eisen wie im Höhenmenü, das seine Schaltfläche ebenfalls behält). Beide Reihen werden gleichmäßig verteilt.

Ist Eisen im Texturenmenü aktiv, entfällt die Eisen-Schaltfläche im Höhenmenü (Einstellung).

**Maske.** Eine Schaltfläche (halb ausgefülltes Quadrat) oben links im Menü des Landschaftseditors. Ist sie aktiv, ändern Naturwerkzeuge (Höhen, Texturen, Wasser, Bäume und Sträucher, Felsen und Pipette) nur Felder mit derselben Textur wie das zuerst angeklickte Feld, sodass du eine Bodenart bemalen kannst, ohne angrenzende Felder zu berühren. Nach dem Loslassen wählt der nächste Klick die Zieltextur neu.

## Wasser

Das Wassermenü erhält zwei Flussdekorationen aus dem Editor des ersten Stronghold zurück, die Crusader weiterhin unterstützt, aber ohne Schaltflächen:

- **Gischt:** weißes Wasser und aufsteigende Gischt wie unter einem Wasserfall auf jedem Flussfeld unter dem Pinsel. Kann auch auf Meeresfeldern gesetzt werden, die dann zu Fluss mit Gischt werden (Einstellung).
- **Kleine Wellen:** auf dem einzelnen Flussfeld unter dem Mauszeiger.

Beide gelten nur für Flussfelder und werden mit der Karte gespeichert (siehe `docs/river-decorations.md` im Repository des Moduls).

## Felsen

- **Wegweiser auf Gefechtskarten.** Gefechtskarten erhalten dasselbe Felsenmenü wie Szenariokarten inklusive Wegweiser.
- **Zufällige Drehung in der Vorschau.** Bei gewählter Zufallsdrehung dreht sich der Felsen einmal pro Sekunde statt jeden Frame, sodass die Vorschau unter der Maus genau den platzierten Felsen zeigt.
- **Variantenleiste.** Eine Leiste über dem Felsenmenü zeigt die vier Varianten der gewählten Felsengröße in ihrer Platzierungsdrehung (inklusive Zufallsdrehung). Klicke eine an, um nur diese Variante zu setzen; ein weiterer Klick darauf oder auf eine Schaltfläche im Felsenmenü aktiviert wieder den automatischen Wechsel.
- **Unsichtbare Felsen.** Ein Kontrollkästchen rechts neben den Felsen-Schaltflächen. Angehakt ist jeder gesetzte Felsen sofort ein unsichtbarer Felsen (der „2k-Steine-Trick“), ohne zuvor 4000 Felsen setzen zu müssen: Die Felder sind blockiert, aber es wird kein Felsen gezeichnet, sodass der bisherige Boden sichtbar bleibt. Abhaken setzt wieder normale Felsen. Unsichtbare Felsen werden ganz normal in der Karte gespeichert.
- **Unsichtbare Felsen radieren.** Der Landschaftsradierer entfernt auch unsichtbare Felsen und gibt die Felder wieder frei – kein Strauch-Trick mehr nötig.
- **Zusätzlicher kleiner Felsen.** Bei den kleinsten Felsen bietet die Leiste eine fünfte, vom Editor sonst nie gesetzte Variante, die normal in der Karte gespeichert wird.
- **Verlorene Felsen entfernen.** Eine Schaltfläche unten rechts im Felsenmenü. Durch Heben/Senken beschädigte Felsen, deren Felder danach mit Sträuchern überdeckt wurden, bleiben ohne Feld in der Felsenliste und belegen jeweils einen der 4000 Plätze. Die Schaltfläche entfernt alle solchen Einträge; ihr Hinweis nennt die Anzahl.

## Höhen

- **Maximale Höhe.** Das Werkzeug „Maximale Höhe“ aus dem ersten Stronghold ist rechts neben „Minimale Höhe“ zurück und setzt Gelände unter dem Pinsel auf Höhe 156.
- **Optionen für Höhenwerkzeuge.** Ist ein Höhenwerkzeug gewählt, bietet eine Leiste über dem Höhenmenü (von unten nach oben):
  - **Bodentexturen zurücksetzen** (anfangs aus): ob Höhenwerkzeuge den Boden wieder auf die Grundtextur (und Plateaus auf Erde) zurücksetzen. Aus ändert nur die Höhe.
  - **Felsenfelder aufbrechen** (anfangs aus): ob Heben, Senken, Angleichen, Hügel und Berg berührte Felsen wie im Original aufbrechen (die Felder werden unsichtbar und begehbar, der Felsen bleibt). Aus bleiben Felsen ganz.
  - **Wasser ignorieren** und **Ackerland ignorieren** (anfangs aus): lässt Meer, Fluss, Furt, Sumpf und Burggraben bzw. Gestrüpp, dichtes Gestrüpp und Oasengras unberührt.
  - Für Heben, Senken und Angleichen: **An Bereich anpassen** (anfangs an; aus bleiben Felder außerhalb unverändert), **Umkehren** (nur Angleichen: raut den Boden auf und erzeugt auf flachem Boden zufällige Unebenheiten; Strg halten bewirkt dasselbe, einstellbar), den **Höhenbereich** (zweiseitiger Regler, anfangs 8 bis 156, beliebig von 0 bis 255) und die **Stärke** (Schrittweite pro Anwendung; 7 entspricht dem Originaltempo beim Angleichen). Regler per Ziehen bedienen.
  - **Felsenhöhen ändern** (Auswahl, anfangs Ganzer Felsen): *Nur Feld* verschiebt nur Felder unter dem Pinsel, *Ganzer Felsen* bewegt alle Felder des Felsens gemeinsam, *Felsen löschen* entfernt den Felsen (wie „Minimale Höhe“).
  Bereich, An Bereich anpassen, Umkehren und die Ignorieren-Kästchen werden beim Verlassen des Editors zurückgesetzt. Heben und Senken laufen an der niedrigsten und höchsten Höhe nicht mehr über.

## Burgmodus

Im Baumenü des Burgmodus im Karteneditor:

- **Gebäudezähler** über der Minikarte:
  - alle Gebäude auf der Karte gegen das Spiellimit (inkl. Bergfrieden, Landschaftsgebäuden und Gebäudeteilen, die ebenfalls Listenplätze belegen);
  - alle Spielergebäude aller Spieler zusammen;
  - die Spielergebäude des aktuellen Spielers.

  Spielergebäude sind jene, die ein Feind zerstören kann.
- **Turmruinen.** Bei geöffnetem Türme-Menü bietet eine Leiste darüber die Ruinen aller fünf Türme.
- **Tunneleingang und Belagerungszelte.** Im Militärbaumenü bietet die Leiste bei gewählter Tunnelgräbergilde einen Tunneleingang und bei gewählter Baumeistergilde die sechs Belagerungszelte.
- **Statue und Schreine.** Die ungenutzte 2×2-Statue, der 2×2-Schrein und der 1×1-Schrein am Ende der jeweiligen Variantenleiste oder (bei deaktivierten Gebäudevarianten) in einer Leiste über „Gute Dinge“.
- **Gebäudevarianten.** Bei gewähltem Garten (2×2, 3×3 oder 4×4), Statue, Schrein oder Latrine zeigt eine Leiste über dem Menü alle Varianten als Kartenansicht; eine gewählte Variante bleibt stehen, statt sekündlich weiterzuschalten. Dasselbe gilt für Hütten (und die zerstörte Kathedrale). Ein Klick im Menü kehrt zum automatischen Wechsel zurück.
- **Mehrere Bergfriede.** Ein neuer Bergfried entfernt nicht mehr den früheren Bergfried (oder dessen Lagerfeuer). Der neueste ist der aktive Bergfried; die anderen bleiben als Gebäude bestehen.
- **Mehrere Lager- und Rekrutierungsgebäude.** Kasernen, Söldnerlager, Gilden und andere sonst einmalige Gebäude werden beim Platzieren weiterer Exemplare nicht mehr entfernt, und zusätzliche Vorratslager, Kornspeicher und Waffenkammern müssen das erste nicht mehr berühren. Beliebig viele davon dürfen leer bleiben (sonst max. 8 leere Kornspeicher/Waffenkammern und 32 leere Vorratslager je Spieler).
- **Turmmangen und Turmballisten überall.** Können auf jedem freien Feld ohne Einheit platziert werden: Boden, Mauern, Tore, beliebige Türme oder Bergfried. Auf eigenen Quadrat- und Rundtürmen funktionieren sie wie gewohnt.
- **Bergfried ohne Lagerfeuer oder Vorratslager.** Bei gewähltem Bergfried bietet die Leiste darüber **Nur Bergfried** (Bergfried und Eingang) sowie **Ohne Vorratslager** (Bergfried, Eingang und Lagerfeuerplatz). Vorschau und Platzprüfung beziehen sich nur auf diese Teile.
- **Beschädigte Mauern.** Bei gewählten Treppen, niedrigem Wall, hohem Wall oder Zinnen bietet die Leiste **Beschädigt**: Mauern erhalten die Krone beschädigter Mauern bei gleicher Höhe.
- **Zerstörte Kathedrale.** Bei gewählter Kathedrale bietet die Leiste **Ruine**: die zerstörte Grafik aus der Mission „Kerak“. Im Spiel funktioniert sie dennoch als vollständige Kathedrale. Auch die Pipette übernimmt sie als Ruine. Benötigt die spielinterne `gm/tile_churches.gm1` (ältere oder ersetzte Dateien enthalten keine Ruine, dann bleiben Kathedralen ganz).
- **Gegrabener, geplanter und dauerhafter Burggraben.** Im Torhaus-Menü bietet die Leiste **Gegraben** (Standard), **Geplant** (zum Ausheben markiert wie im Spiel) und **Dauerhaft** (kann im Spiel weder zugeschüttet noch gelöscht werden).
- **Burggraben auf Sumpf.** Lässt sich wieder auf Sumpf setzen; der Sumpf bleibt darunter erhalten und kehrt beim Zuschütten zurück.
- **Graben entfernen behält den Boden.** „Burggraben entfernen“ ändert nur Felder mit gegrabenem oder geplantem Graben, stellt die Bodenhöhe wieder her und lässt die Textur unverändert.
- **Gebäudenamen weiter links.** Der Name unter dem Mauszeiger („Bergfried von Spieler 1“) rückt 100 Pixel nach links und überlappt nicht mit dem Gebäudezähler.
- **Barriere.** Im freien Feld unten rechts im Ruinen-Menü steht eine wieder löschbare 1×1-Barriere bereit.

## Herden

Sind Hirsch, Löwe, Hase oder Kamel gewählt, zeigt eine Leiste über dem Tiere-Menü die Herdengröße (fester plus zufälliger Anteil) und das Gruppenverhalten. Mit dem Kontrollkästchen entspricht die Größe dem Pinsel: 2 × Pinselgröße − 1 Tiere (Pinsel 1 setzt einzelne Tiere, Pinsel 7 Herden mit 13 Tieren).

Rote Papierkorb-Schaltflächen im Tiere-Menü: rechts neben Krähen **Alle Krähen löschen** (Bäume bleiben), rechts neben Möwen **Alle Möwen löschen** und ganz rechts **Alle Tiere löschen** (wie Alt + E; Vögel bleiben).

Sind weniger als 200 Herden und Gruppen frei, zeigt eine Zeile am oberen Bildschirmrand die verbleibende Zahl an, wie die Einheitenzeile des Spiels.

## Radierer

Der Radierer entfernt auch Möwen über den radierten Feldern. Bei gewähltem Radierer wählt eine Leiste über dem Menü, was entfernt wird:

- **Alles** – alles wie bisher.
- **Tiere** – Tiere, Krähen (Bäume bleiben) und Möwen.
- **Einheiten** – alle übrigen Einheiten.
- **Gebäude** – Gebäude, Bergfriede, Ruinen und Mauern.
- **Vegetation** – Bäume und Sträucher.
- **Felsen** – Felsen einschließlich unsichtbarer Felsen.

## Karteneinstellungen

- **Gesperrte Karten anzeigen:** Kontrollkästchen im Laden-Dialog des Editors; angehakt werden auch gesperrte Karten angezeigt.
- **Schaltfläche Karteneinstellungen** im Kartenmenü (bei Speichern und Beenden), rechts neben Ausgeglichen/Unausgeglichen bzw. Invasion/Wirtschaft. Öffnet das Menü von Alt + ,.
- **Das Menü Karteneinstellungen** ist erweitert: Titel, Einzelspieler und Mehrspieler; unter Einzelspieler die Kartentypen Belagerung, Invasion, Wirtschaft und Freies Bauen; unter Mehrspieler die Größen 160, 200, 300, 400 und Benutzerdefiniert sowie ein Kartengrößen-Regler von 10 bis 400 (wird beim Loslassen der Maustaste angewendet); Ausgeglichen und König des Hügels; Karte sperren; und Zurück (Esc und Alt + , schließen es weiterhin). Alle diese Funktionen waren im Spielcode bereits vorhanden; nur die Schaltflächen fehlten. „Karte sperren“ setzt die Missionssperre, wodurch die Karte in der Gefechtsliste bleibt, aber im Laden-Dialog des Editors erst mit „Gesperrte Karten anzeigen“ sichtbar ist.

## Bilder

Die Schaltflächen für Apfelbaum und Kies nutzen die Dateien im Ordner `images` des Moduls: `apple.png`, `apple_hover.png`, `apple_selected.png` sowie `gravel.png`, `gravel_hover.png`, `gravel_selected.png` (normal, Maus darüber, gewählt). Ersetze sie durch eigene Bilder, um die Schaltflächen anzupassen.

## Pinsel

Die Pinsel des Spiels zählen das Feld unter dem Mauszeiger doppelt und lassen oben links eine Ecke der Form aus – sowohl in der Vorschau als auch beim Setzen. Mit dieser Einstellung hat jeder Pinsel seine vollständige Form.

## Rückgängig und Wiederherstellen

Zwei Pfeilschaltflächen oben links im Karteneditor (im Landschafts- und Burgmenü): Die linke macht die letzte Kartenänderung rückgängig (Gebäude, Bäume, Felsen, Tiere, Texturen, Wasser, Höhen), die rechte stellt sie wieder her. Ohne mögliche Aktion ist die Schaltfläche ausgegraut. Bis zu 20 Schritte werden gespeichert. Jeder Klick zählt als ein Schritt, und ein gedrückt gehaltener Pinselstrich wird in einem Schritt rückgängig gemacht. Klicks ohne Änderung erzeugen keinen Schritt und stören Wiederherstellen nicht. Eine neue Aktion nach Rückgängig verwirft den Wiederherstellen-Verlauf; das Laden einer neuen Karte startet den Verlauf neu.

## Pipette

Eine Pipetten-Schaltfläche sitzt in der linken Spalte des Landschaftseditors über der Pinselgröße (Pinselgröße, Lineal und Radierer rücken etwas nach unten). Bei Auswahl erscheint eine Leiste über dem Menü – **Höhen**, **Texturen**, **Objekte**, **Alle** – und darüber eine Zeile mit dem aufgenommenen Inhalt.

- **Aufnehmen:** Feld anklicken (die Pipette zeigt ein einzelnes Feld).
- **Übertragen:** Klicken oder ziehen, um Höhen, Texturen oder beides auf die Felder unter dem Pinsel zu übertragen. Höhen lassen die Bodentextur unberührt, Texturen die Höhen.
- **Objekte:** Klicke ein Gebäude, eine Mauer, einen Baum oder Felsen an. Gebäude und Mauern werden wie über ihr eigenes Menü für den ursprünglichen Spieler platziert (dessen Wappen wird gewählt); Bäume (gleiche Art und Wachstumsstufe oder gefällt mit gleicher Stammzahl) und Felsen (gleiche Art und Drehung) wie mit den jeweiligen Werkzeugen samt Ziehen, Vorschau und Prüfungen. Danach kehren Pinsel, Felsendrehung und Fällzustand zurück. Die Baumstufe richtet sich nach „Pinselgröße bestimmt Wachstumsstufe“.
- **Alle** übernimmt zusätzlich einen Baum oder 1×1-Felsen und setzt ihn auf jedes freie Feld unter dem Pinsel.
- Höhen werden nicht auf Meer, Strand, Sumpf, Burggraben, Felsen, Mauern oder Gebäude übertragen; Texturen nicht auf Felsen, Mauern oder Gebäude. Klippenfelsen an steilen Kanten werden bereinigt und an weiterhin steilen Kanten neu erzeugt. Halten von **Alt** überträgt Höhen und Texturen dennoch auf jedes Feld (Felsen bleiben stehen; experimentell).
- Erneutes Wählen der Pipette oder einer ihrer Arten leert sie. **P** wählt die Pipette und schaltet beim erneuten Drücken zur nächsten Art weiter. Halten von **Strg** nimmt ein neues Feld auf, während die Pipette gefüllt ist; Loslassen überträgt wieder. Alle drei Tasten lassen sich ändern oder deaktivieren.
- Rückgängig macht Pipettenstriche wie jede andere Änderung rückgängig.

## Menü immer aktuell halten

Das Spiel zeichnet das Editormenü nur neu, solange der Mauszeiger darüber liegt. Ändert sich etwas, während die Maus auf der Karte ist (z. B. Werkzeugwechsel per Taste oder aktualisierte Tierzähler), bleibt das Menü sonst veraltet. Mit dieser Einstellung wird das Menü im Karteneditor laufend aktualisiert; außerhalb des Editors ändert sich nichts.

## Ressourcenraster

Zeichnet das Raster über die Karte, das die KI bei der Standortsuche für ihre Steinbrüche,
Eisenminen, Pechförderer und Holzfäller nutzt: Blöcke aus 5 × 5 Feldern. Ein Steinvorkommen
innerhalb eines Blocks ist für die KI wertvoller als dasselbe Vorkommen über vier Blöcke
verteilt. Außerdem zeichnet es die vier Linien, an denen sich der Burgplan der KI je nach
Position des Bergfrieds dreht, sowie in jedem Block die Felder, die eine KI-Eisenmine belegen
würde.

- **Alt + G** blendet es im Karteneditor ein oder aus. Eine andere Kombination aus Alt + Taste
  lässt sich in den Einstellungen wählen, oder das Kürzel kann in Custom Hotkeys geändert werden.
- Standardmäßig erscheint es nur in der flachen Ansicht (Leertaste), in der die Linien exakt auf
  dem Boden liegen, und bleibt in der V-Ansicht ausgeblendet.
- **Raster auch im Spiel erlauben** lässt dich die Linien in einem Testspiel prüfen (mit Custom
  Hotkeys das Kürzel für das Spiel dort belegen).
- Die Farben des Rasters, der Grenzen und der Grundfläche der Eisenmine lassen sich ändern.
- Es wird nichts in der Karte gespeichert.

## Gut zu wissen

- Funktioniert mit Stronghold Crusader und Stronghold Crusader Extreme. Die Limits werden aus dem Spiel gelesen, sodass Extreme sein eigenes (höheres) Einheitenlimit anzeigt.
- Bäume, Sträucher und Felsen werden nach ihren belegten Plätzen in den Spiellisten gezählt, für die die Limits gelten. Ein Strauchstapel auf einem Feld zählt jeden einzelnen Strauch darin.
- Nichts wird zusätzlich in die Karte gespeichert.
