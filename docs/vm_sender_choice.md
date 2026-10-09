# Absenderadresse beim Antworten wählen

Beim Antworten per E-Mail kann ein Agent wählen, von welcher Adresse die Mail
rausgeht. Ohne Auswahl ändert sich nichts: Die Mail geht von der Adresse der
Gruppe des Tickets raus, wie bisher.

## Was der Agent sieht

Im Antwortfeld (Art "E-Mail") erscheint über "An" ein Feld "Von". Die Adresse der
Gruppe steht oben und ist vorausgewählt, dahinter "(Standard)". Gibt es keine
weitere nutzbare Adresse, erscheint das Feld nicht und die Anfrage an den Server
ist byte-gleich zu vorher.

## Welche Adressen zur Auswahl stehen

Eine Adresse erscheint nur, wenn alle Punkte stimmen:

- Sie ist als Absenderadresse im System angelegt und aktiv.
- Sie ist mit einem Kanal verknüpft.
- Dieser Kanal ist aktiv und kann E-Mails versenden (E-Mail-Konto, Google,
  Microsoft 365 oder Microsoft Graph).

Freitext wird nie angenommen. Der Server prüft die Auswahl beim Anlegen der Mail
noch einmal; eine nicht erlaubte Adresse wird mit einer deutschen Fehlermeldung
abgelehnt ("Die gewählte Absenderadresse steht nicht zur Verfügung."), es wird
dann nichts gesendet.

Die Mail wird über genau den Kanal versendet, mit dem die gewählte Adresse
verknüpft ist, und der Name im Absenderfeld folgt der Systemeinstellung zum
Absendernamen wie bisher. Steht dort "Agentenname | Adressname", wird der Name der
gewählten Adresse verwendet, nicht der der Gruppe.

## Zweites gemeinsames Postfach anbinden (Beispiel keyaccount@)

Wir verwenden bewusst **einen Kanal pro Postfach**. Ein Kanal, der im Namen
mehrerer Postfächer sendet ("Senden als"), würde zusätzliche Rechte pro Postfach
und pro Absender in Microsoft 365 brauchen und scheitert still, wenn eines fehlt.
Mit einem eigenen Kanal gilt für jedes Postfach dieselbe, bekannte Rechtelage.

1. **Postfach in Microsoft 365 vorbereiten.** Das gemeinsame Postfach muss
   existieren. Das Konto, mit dem sich der Kanal anmeldet, braucht darauf die
   Rechte "Vollzugriff" und "Senden als" (alternativ "Im Auftrag senden", dann
   steht beim Empfänger "im Auftrag von"). Ohne "Senden als" lehnt Microsoft
   die Mail ab oder ersetzt den Absender.
2. **Kanal anlegen.** Im Adminbereich unter Kanäle, E-Mail, ein weiteres
   Microsoft-365-Konto (Graph) verbinden. Beim Anmelden das Konto mit den Rechten
   aus Schritt 1 verwenden und als Postfachart "Gemeinsames Postfach" mit der
   Adresse des Postfachs eintragen. Die App-Berechtigungen des Kanals
   (`mail.readwrite`, `mail.readwrite.shared`, `mail.send`, `mail.send.shared`)
   sind dieselben wie beim ersten Postfach, die Zustimmung des Mandanten gilt für
   die App und muss nicht erneut erteilt werden.
3. **Zielgruppe für eingehende Mails wählen** (zum Beispiel die Gruppe
   "Key Account"). Das Häkchen, das die Adresse zur Absenderadresse dieser Gruppe
   macht, **nicht** setzen, wenn die Gruppe ihre bisherige Adresse behalten soll.
   Sonst ändert sich der Standard der Gruppe.
4. **Absenderadresse anlegen oder prüfen.** Unter Kanäle, E-Mail, Adressen muss
   es einen Eintrag mit der Adresse des Postfachs geben, der mit dem neuen Kanal
   verknüpft ist (Name zum Beispiel "DentaTec Key Account"). Der Name erscheint im
   Absenderfeld der Mail. Ein Eintrag ohne Kanal ist inaktiv und wird nicht
   angeboten.
5. **Prüfen.** Als Agent ein Ticket öffnen, "Antworten" wählen: Das Feld "Von"
   zeigt jetzt beide Adressen. Eine Testmail an eine eigene Adresse senden und den
   Absender prüfen.

## Antworten und Zuordnung

Antwortet der Kunde auf die Mail, kommt die Antwort im Postfach der gewählten
Adresse an. Sie wird über Ticketnummer im Betreff und Mail-Verweise dem
bestehenden Ticket zugeordnet; ein neues Ticket entsteht nur, wenn der Kunde den
Verlauf verlässt. Die Gruppe, die für das zweite Postfach als Ziel eingestellt
ist, gilt nur für Mails, die zu keinem Ticket passen.

## Prüfliste für den Betrieb

- Absender lässt sich nicht wählen: Ist der Eintrag unter Adressen aktiv und
  mit einem **aktiven** Kanal verknüpft? Ein deaktivierter oder gelöschter Kanal
  macht die Adresse unbrauchbar, auch wenn sie noch in der Liste steht.
- Mail kommt mit falschem Absender oder gar nicht an: In Microsoft 365 fehlt
  "Senden als" auf dem Postfach (siehe Schritt 1). Der Fehler steht am
  Artikel unter "Zustellstatus".
- Sicherheit: Es wird nur gesendet, was ein Administrator als Absenderadresse
  mit Kanal angelegt hat. Ein Agent kann keine Adresse frei eintippen.

## Technischer Überblick (für Entwickler)

- Regel und Prüfung: `app/models/vm_sender_choice.rb`.
- Wirkung beim Anlegen einer E-Mail: `Ticket::Article::AddsMetadataEmail` liest
  den Artikel-Parameter `preferences.vm_sender_email_address_id` und setzt
  `preferences.email_address_id` und `from` danach. Den Versand über den
  richtigen Kanal erledigt `TicketArticleCommunicateEmailJob` seit jeher anhand
  von `email_address_id`.
- Liste für das Antwortfeld: `GET /api/v1/vm_sender_addresses?ticket_id=`.
- Oberfläche: `article_action/vm_sender_choice.coffee`, eingehängt über die
  bestehenden Hooks des Antwortfelds, ohne Änderung an `article_new`.
