QUELLEN:  
https://docs.paperless-ngx.com/administration/  
https://docs.paperless-ngx.com/configuration/  
https://github.com/paperless-ngx/paperless-ngx  
https://ocrmypdf.readthedocs.io/en/latest/languages.html  
https://www.technik22.de/d/937-paperless-ngx-tika-gotenberg/2  
Dokumente werden hier abgespeichert: /opt/paperless_data/media  

1. Paperless über PVE Helper Script installieren und anpassen  
Siehe: https://community-scripts.github.io/ProxmoxVE/scripts?id=paperless-ngx  

* Sicherheitshalber das Password von Root nochmal setzen:  
~~~
passwd root
~~~

* Root SSH Konfig gewähren:
~~~
nano /etc/ssh/sshd_config
~~~
~~~
PermitRootLogin yes
~~~
~~~
systemctl restart sshd.service
~~~

* Zugansdaten finden:
~~~
cat ~/paperless-ngx.creds
~~~

* Installiere OCR Deutsch:
~~~
apt-get install tesseract-ocr-deu
~~~

* Paperless Konfiguration anpassen:
~~~
nano /opt/paperless/paperless.conf
~~~
~~~
PAPERLESS_OCR_LANGUAGE=deu
PAPERLESS_TIME_ZONE=Europe/Berlin
PAPERLESS_OCR_LANGUAGES=eng tur
~~~

2. Docker installieren:  
Quelle: https://www.thomas-krenn.com/en/wiki/Docker_installation_on_Debian_12  
* Installiere die für die Installation erforderlichen Pakete:
~~~
apt-get update
~~~
~~~
apt-get install ca-certificates curl
~~~
~~~
install -m 0755 -d /etc/apt/keyrings
~~~
~~~
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
~~~
~~~
chmod a+r /etc/apt/keyrings/docker.asc
~~~

* Füge das Repository zu den Apt-Quellen hinzu:
~~~
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
~~~
~~~
apt-get update
~~~

* GPG-Schlüssel herunterladen und Repository im System speichern:
~~~
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
~~~
~~~
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" |tee /etc/apt/sources.list.d/docker.list > /dev/null
~~~
~~~
apt update 
~~~

* Installiere die Docker-Pakete:
~~~
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
~~~

3. Den Start Script sichern und bearbeiten
* Sichere Startscript:
~~~
cp /opt/paperless/scripts/start_services.sh /opt/paperless/scripts/start_services.sh.bak
~~~

* Startscript bearbeiten:
~~~
nano /opt/paperless/scripts/start_services.sh
~~~

Inhalt löschen und das hinzufügen:
~~~
#!/usr/bin/env bash

docker run --restart=always -p 3000:3000 -d gotenberg/gotenberg:latest gotenberg --chromium-disable-javascript=true --chromium-allow-list="file:///tmp/.*"
docker run --restart=always -p 9998:9998 -d docker.io/apache/tika:latest
~~~

* Das skript einmal manuell ausführen:
~~~
/opt/paperless/scripts/start_services.sh
~~~

4. Paperless Konfiguration anpassen
* Konfigurationsdatei anpassen:
~~~
nano  /opt/paperless/paperless.conf
~~~
~~~
PAPERLESS_TIKA_ENABLED=true
PAPERLESS_TIKA_ENDPOINT=http://0.0.0.0:9998
PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://0.0.0.0:3000
~~~

* Container neustarten:
~~~
reboot
~~~

5. SMB-Server im LXC einrichten
* scan User in Linux anlegen mit
~~~
adduser scan
~~~

* Samba installieren:
~~~
apt install samba -y
~~~

* Denselben scan User verwenden, dann sind Rechte konsistent:
~~~
smbpasswd -a scan
~~~

* Samba-Konfiguration sichern und anpassen:
~~~
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
~~~

* Am Ende der Datei einen Share für den Consume-Ordner eintragen:
~~~
nano /etc/samba/smb.conf
~~~
~~~
[consume]
   path = /opt/paperless_data/consume
   browseable = yes
   writable = yes
   valid users = scan
   force user = scan
   force group = scan
   create mask = 0664
   directory mask = 0775
~~~

* Wenn gewünscht Freigeba homes deaktivieren indem man unter [homes] folgendes einfügt:
~~~
available = no
~~~

* Samba neu starten:
~~~
systemctl restart smbd
~~~
~~~
systemctl enable smbd
~~~

* Den Owner von consume Ordner ändern und die Berechtigungen anpassen:

~~~
chown -R scan:scan /opt/paperless_data/consume
~~~
~~~
chmod -R 775 /opt/paperless_data/consume
~~~

* Jetzt kannst du vom Scanner oder Windows/macOS-Rechner verbinden:
Pfad: \\<LXC-IP>\consume
Benutzer: scan
Passwort: das bei smbpasswd gesetzte.

* Zum Schluss kontrollieren ob irgendein Dienst nicht arbeitet:
~~~
systemctl --failed
~~~
~~~
systemctl --type=service --state=running list-units
~~~
~~~
journalctl -u <UNITNAME>
~~~

6. Sonstiges
* Beispiel für Speicherpfade in Paperless:  
{{ owner_username }}/10_Persönliche-Dokumente/{{ correspondent }}/{{ created_year }}/{{ created_year }}{{ created_month }}{{ created_day }}_{{ title }}  

* Mit Powershell Tika prüfen:  
Invoke-WebRequest -UseBasicParsing -Uri "http://<LXC-IP>/tika" -InFile "C:\Users\Administrator\Downloads\PSVC.docx" -Method Put  

* Ob Tika und Gotenberg läuft:  
http://<LXC-IP>:9998/  
http://<LXC-IP>:3000/health  

* Weiteres  
[Real World Examples] - Document Types  
https://github.com/paperless-ngx/paperless-ngx/discussions/1833  
https://digital-cleaning.de/index.php/paperless-ngx-teil-17-unterordner-des-consume-verzeichnisses-nutzen/  

https://www.reddit.com/r/selfhosted/comments/sdv0rr/paperless_ng_which_tags_document_types/  
So habe ich Paperless zu Hause eingerichtet...  

Dokumenttypen beziehen sich auf die allgemeine Art des betreffenden Dokuments. Handelt es sich um einen Brief? Eine Quittung? Eine Rechnung?  
	Jeder Fall ist anders, aber dies sollte Ihr allgemeinster Bereich sein. Sie möchten nur eine ungefähre Vorstellung davon bekommen.  
	Mein Dokumenttyp „Quittungen” enthält beispielsweise Quittungen, die ich einscanne, aber auch Bestätigungen meiner Schuldner,  
	dass ich eine Rechnung bezahlt habe, oder eine E-Mail von Cash App, dass ich Bitcoin verkauft habe.  

Der Korrespondent bezieht sich auf die Person/Organisation, mit der Sie in dem Dokument kommunizieren.  
	Eine Rechnung von Ihrer Kreditkarte hätte beispielsweise Capital One als Korrespondenten, während eine Kopie Ihrer W2 unter IRS fallen könnte.  
	Auch hier können Sie wieder weit gefasst sein, da der Versuch, es einzugrenzen, Sie in den Wahnsinn treiben wird.  
	
Tags werden verwendet, um die folgenden grundlegenden Fragen zu beantworten:  
	Auf wen bezieht sich das Dokument? In meinem Fall habe ich Tags für mich selbst, meine Frau, die Kinder und die Hunde.  
	Sie haben alle die gleiche Farbe, um dies leicht zu kennzeichnen. Beachten Sie, dass dies NICHT dasselbe ist wie der Korrespondent.  
	Worauf bezieht sich das Dokument? Bezieht es sich auf Ihren Autokredit? Bezieht es sich auf die Instandhaltung Ihres Hauses?  
	Markieren Sie diese Tags mit einer anderen Farbe, damit Sie sie leicht erkennen können.  
	Wann sind die Informationen in diesem Dokument relevant? Handelt es sich um eine Rechnung von vor zwei Jahren?  
	Bezieht es sich auf Ihre Steuern für 2022? Ich persönlich erstelle Tags für das Jahr, in dem ich die Rechnung erhalten habe,  
	da dies das Sortieren erleichtert. Bei Bedarf können Sie dies weiter nach Monaten unterteilen.  
	Ich erstelle auch Tags für spezielle Kategorien, die ich nachverfolgen muss. Ich habe beispielsweise ein Tag für alle Dokumente,  
	die wir im kommenden Jahr für unsere Steuern benötigen, oder für wichtige Dokumente (Geburtsurkunden usw.).  
	Dies hilft bei der weiteren Unterteilung.  

OCR ist hilfreich, sollte aber nicht die einzige Grundlage für Ihre Suche sein.  
Wenn Sie mindestens 1–2 Metadatenfelder verwenden und anschließend eine Volltextsuche durchführen,  
finden Sie in 99 % der Fälle das richtige Dokument. Ja, bei einer geringen Anzahl von Dokumenten finden Sie wahrscheinlich allein mit OCR,  
was Sie suchen. Aber was passiert, wenn Sie 48 Monate lang gesammelte Belege sortieren müssen?  

Eine letzte Anmerkung: Wie bei jedem Datensystem sind die Informationen, die Sie bei einer Suche erhalten, nur so gut wie die Daten,  
die Sie eingeben. Garbage in, garbage out. Nehmen Sie sich die Zeit und markieren Sie mindestens ein Metadatenfeld und ein paar Tags.  

Rechnung  
Beschreibung: Eingehende oder ausgehende Rechnungen von Lieferanten oder Kunden.  
Tags: Finanzen, Buchhaltung  
Beispiel-Dateien: PDF-Rechnungen, E-Mail-Rechnungen  

Vertrag  
Beschreibung: Arbeitsverträge, Mietverträge, Dienstleistungsverträge.  
Tags: Recht, Personal  
Beispiel-Dateien: unterschriebene PDF-Dokumente  

Quittung  
Beschreibung: Zahlungsbelege, Kassenzettel.  
Tags: Finanzen, Ausgaben  
Beispiel-Dateien: gescannte Belege  

Versicherung  
Beschreibung: Policen, Schadensmeldungen, Beitragsabrechnungen.  
Tags: Versicherung, Dokumentation  

Behördendokument  
Beschreibung: Steuerbescheide, amtliche Schreiben, Meldebescheinigungen.  
Tags: Behörde, Steuern  

Bankdokument  
Beschreibung: Kontoauszüge, Kreditverträge, Finanzberichte.  
Tags: Bank, Finanzen  

Technische Dokumentation  
Beschreibung: Handbücher, Installationsanleitungen, Wartungsprotokolle.  
Tags: Technik, IT  

Korrespondenz  
Beschreibung: Briefe, E-Mails, geschäftliche Kommunikation.  
Tags: Kommunikation  

Personalakte  
Beschreibung: Mitarbeiterdokumente, Gehaltsabrechnungen.  
Tags: HR, Personal  

Sonstiges  
Beschreibung: Alles, was nicht in die obigen Kategorien passt.  
Tags: Allgemein  
