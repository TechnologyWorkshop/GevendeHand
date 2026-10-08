# Windows 11-upgrade: "De door het systeem gereserveerde partitie kan niet worden bijgewerkt"

Deze handleiding helpt bij de foutmelding die Windows Setup / Windows Update toont bij het upgraden naar Windows 11:

> **De door het systeem gereserveerde partitie kan niet worden bijgewerkt.**
> *(Engels: "We couldn't update the system reserved partition", vaak met foutcode `0xc1900104` of `0x800f0922`)*

## Wat is de oorzaak?

Je computer heeft een kleine, verborgen partitie met de opstartbestanden van Windows:

| Type pc | Naam van de partitie | Typische grootte |
|---|---|---|
| UEFI / GPT (nieuwere pc's) | **EFI-systeempartitie** | 100–300 MB |
| BIOS (Legacy) / MBR (oudere pc's) | **Door systeem gereserveerd** | 50–500 MB |

Tijdens de upgrade schrijft Windows nieuwe opstartbestanden naar deze partitie. Is er **te weinig vrije ruimte** (vaak minder dan ongeveer 15 MB), dan stopt de upgrade met deze fout. De oplossing is ruimte vrijmaken op die partitie, meestal door de (niet noodzakelijke) taal-lettertypen van de opstartbeheerder te verwijderen.

> ⚠️ **Let op:** je werkt hierbij met de opstartpartitie. Volg de stappen precies. Een fout kan ervoor zorgen dat Windows niet meer opstart.

---

## Stap 1 – Maak een back-up

Zet je belangrijke bestanden (documenten, foto's, enz.) op een externe schijf of in de cloud voordat je verdergaat.

Gebruik je **BitLocker**? Noteer dan je herstelsleutel (`manage-bde -protectors -get C:` of via <https://account.microsoft.com/devices/recoverykey>).

## Stap 2 – Controleer de systeempartitie

**Automatisch (aanbevolen):** voer het script [`scripts/Controleer-Systeempartitie.ps1`](../scripts/Controleer-Systeempartitie.ps1) uit. Het script wijzigt niets; het toont alleen de partitiestijl (GPT/MBR), de grootte en vrije ruimte van de systeempartitie en welke stap hieronder je moet volgen.

1. Klik met de rechtermuisknop op **Start** → **Terminal (Administrator)** of **Windows PowerShell (Administrator)**.
2. Ga naar de map met het script en voer uit:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\Controleer-Systeempartitie.ps1
   ```

**Handmatig:**

1. Druk op **Windows-toets + X** → **Schijfbeheer**.
2. Klik met de rechtermuisknop op *Schijf 0* (links) → **Eigenschappen** → tabblad **Volumes**. Bij *Partitiestijl* staat **GUID-partitietabel (GPT)** of **Master Boot Record (MBR)**.
3. Zoek de partitie **EFI-systeempartitie** (GPT) of **Door systeem gereserveerd** (MBR) en bekijk de grootte.

Ga daarna naar **stap 3A** (GPT) of **stap 3B** (MBR).

---

## Stap 3A – Ruimte vrijmaken op de EFI-systeempartitie (GPT / UEFI)

1. Open **Opdrachtprompt als administrator** (zoek op `cmd` → rechtermuisknop → *Als administrator uitvoeren*).
2. Koppel de EFI-partitie tijdelijk aan stationsletter `Y:`:

   ```cmd
   mountvol Y: /s
   ```

3. Maak eerst een reservekopie van de lettertypen en verwijder ze daarna van de partitie:

   ```cmd
   mkdir C:\BootFontsBackup
   xcopy Y:\EFI\Microsoft\Boot\Fonts C:\BootFontsBackup /e /h /i
   del /q Y:\EFI\Microsoft\Boot\Fonts\*.*
   ```

   Deze lettertypen worden alleen gebruikt voor niet-Latijnse talen in het opstartmenu; Windows start ook zonder ze gewoon op en de upgrade zet ze terug.

4. Ontkoppel de partitie weer:

   ```cmd
   mountvol Y: /d
   ```

5. Start de pc opnieuw op en ga naar **stap 5**.

## Stap 3B – Ruimte vrijmaken op "Door systeem gereserveerd" (MBR / Legacy BIOS)

1. Open **Schijfbeheer** (Windows-toets + X → *Schijfbeheer*).
2. Klik met de rechtermuisknop op **Door systeem gereserveerd** → **Stationsletter en paden wijzigen** → **Toevoegen** → kies letter **Y** → **OK**.
3. Open **Opdrachtprompt als administrator** en voer uit:

   ```cmd
   Y:
   takeown /d y /r /f .
   icacls Y:\* /save C:\drivey_acl.txt /c /t
   icacls . /grant "%USERDOMAIN%\%USERNAME%":F /t
   ```

   (Het tweede `icacls`-commando geeft jouw account tijdelijk volledige rechten; het eerste slaat de oorspronkelijke rechten op zodat je ze later kunt terugzetten.)

4. Maak een reservekopie van de lettertypen en verwijder ze:

   ```cmd
   mkdir C:\BootFontsBackup
   xcopy Y:\Boot\Fonts C:\BootFontsBackup /e /h /i
   del /q Y:\Boot\Fonts\*.*
   ```

5. Zet de oorspronkelijke rechten terug:

   ```cmd
   icacls Y:\ /restore C:\drivey_acl.txt /c /t
   icacls . /grant system:f /t
   icacls Y: /setowner "SYSTEM" /t /c
   ```

6. Ga terug naar **Schijfbeheer**, klik met de rechtermuisknop op **Door systeem gereserveerd** → **Stationsletter en paden wijzigen** → selecteer **Y:** → **Verwijderen**.
7. Start de pc opnieuw op en ga naar **stap 4**.

## Stap 4 – (Alleen MBR) Schijf omzetten naar GPT

Windows 11 vereist **UEFI met Secure Boot**, en dat werkt alleen met een GPT-schijf. Met het ingebouwde hulpmiddel `MBR2GPT` zet je de schijf om zonder gegevensverlies; daarbij wordt ook een nieuwe EFI-systeempartitie van voldoende grootte aangemaakt.

1. Schort BitLocker op als het aanstaat: `manage-bde -protectors -disable C:`
2. Open **Opdrachtprompt als administrator** en controleer eerst of omzetten mogelijk is:

   ```cmd
   mbr2gpt /validate /allowFullOS
   ```

3. Meldt het commando *Validation completed successfully*, zet de schijf dan om:

   ```cmd
   mbr2gpt /convert /allowFullOS
   ```

4. Herstart, open de **BIOS/UEFI-instellingen** (meestal F2, F10, F12 of Del tijdens het opstarten) en zet de opstartmodus van **Legacy/CSM** op **UEFI**. Schakel ook **Secure Boot** en **TPM 2.0** (fTPM/PTT) in.
5. Start Windows en hervat BitLocker indien nodig: `manage-bde -protectors -enable C:`

## Stap 5 – Probeer de upgrade opnieuw

Kies één van deze manieren:

- **Instellingen** → **Windows Update** → *Naar updates zoeken*;
- de **Windows 11-installatieassistent** via <https://www.microsoft.com/nl-nl/software-download/windows11>;
- de **Windows 11-ISO** downloaden via dezelfde pagina, dubbelklikken om te koppelen en `setup.exe` starten.

Tip: voer vooraf **Schijfopruiming** (`cleanmgr`) uit en zorg voor minstens 25 GB vrije ruimte op `C:`.

## Stap 6 – Lukt het nog steeds niet?

- **Partitie vergroten:** maak met een partitieprogramma (bijv. MiniTool Partition Wizard, AOMEI Partition Assistant of EaseUS Partition Master) een paar honderd MB vrij direct naast de systeempartitie en vergroot die partitie. Maak altijd eerst een volledige back-up.
- **Schone installatie:** maak met het *Media Creation Tool* een Windows 11-USB-stick en installeer Windows 11 opnieuw. Setup maakt dan automatisch partities van de juiste grootte aan. **Hierbij gaan bestanden op de systeemschijf verloren** – maak eerst een back-up.

## Fontbestanden terugzetten (optioneel)

Wil je de verwijderde lettertypen na een **mislukte** upgrade terugzetten? Koppel de partitie opnieuw (stap 3A punt 2, of bij MBR stap 3B punt 2 en 3) en kopieer ze terug (bij MBR daarna stap 3B punt 5 en 6 herhalen):

```cmd
xcopy C:\BootFontsBackup Y:\EFI\Microsoft\Boot\Fonts /e /h /i   (GPT)
xcopy C:\BootFontsBackup Y:\Boot\Fonts /e /h /i                 (MBR)
```

## Bronnen

- Microsoft Support: *"We couldn't update system reserved partition" error installing Windows 10* (KB 4010118)
- Microsoft Learn: *MBR2GPT.EXE*
