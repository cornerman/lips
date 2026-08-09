<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `hello` language

Diese Sprache beschreibt ein kleines Terminalprogramm in drei deutschen
Sätzen. Sie akzeptiert genau drei Zeilenformen:

- `sage "<text>" auf dem terminal` — der Text, der beim Start ausgegeben
  wird (Fakt `say.gruss`).
- `warte auf input für den <wort>` — es wird eine Zeile von der Eingabe
  gelesen; das Wort benennt den Wert (Fakt `input.<wort>`) und erscheint im
  Abbruchtext, wenn keine Eingabe kommt ("kein wert eingegeben: namen").
- `sage "<text>" mit dem <wort>` — der Text wird zusammen mit dem
  eingelesenen Wert ausgegeben, durch ein Leerzeichen getrennt (Fakt
  `say.abschied.<wort>`).

Jeder Text in Anführungszeichen ist ein Loch: ändere den Satz, und die
Ausgabe ändert sich mit. Die beiden `sage`-Formen unterscheiden sich am
festen Wortlaut (`auf dem terminal` bzw. `mit dem …`), sind also eindeutig.

**Mechanismus.** Das Verhalten wird als Klauseln gebaut, nicht als
Quelldatei: `gruss` gibt den Starttext aus, `frage` liest eine Zeile (und
bricht mit `die` ab, wenn nichts kommt), `abschied` gibt Text und Wert aus,
`main` ruft die drei in der Satzreihenfolge auf. Das gebaute Programm wird
über `site` benannt (der Befehlsname ist der Instanzname der Datei, also der
Dateibasisname) und mit `environment.systemPackages` systemweit installiert.

**Beobachtungen.** `claim.gruss` prüft, dass der Starttext wirklich
ausgegeben wird; `claim.frage`, dass die gelesene Zeile durchkommt;
`claim.abschied-<wort>` läuft `main` ganz durch und prüft die zweite
ausgegebene Zeile („<text> Welt"). Die Expects halten die beiden Texte des
Programms an diesen Beobachtungen fest.

**Was ich erfinden musste.** Das Programm nennt keine Beispieleingabe, also
speisen die Beobachtungen die Zeile `Welt` ein (Konfidenz 0.85, siehe die
because-Zeilen). Wer eine echte Beispielzeile im Programm nennen will,
braucht dafür einen neuen Satz und damit einen neuen Mint. Weil `main` die
drei Klauseln namentlich aufruft, verlangt die Sprache alle drei Zeilen:
fehlt eine, fragt lips über die demand-Fragen nach.
