# Windows 11-upgrade: "De door het systeem gereserveerde partitie kan niet worden bijgewerkt"

Je krijgt deze melding tijdens de upgrade naar Windows 11 (soms met foutcode
**0xc1900104** of **0x800f0922**):

> De door het systeem gereserveerde partitie kan niet worden bijgewerkt.

## Oorzaak

Je pc is meestal **niet** te zwak voor Windows 11. De oorzaak is dat de kleine,
verborgen **systeempartitie** te vol is:

- **EFI-systeempartitie** (pc's met UEFI / GPT-schijf, de meeste moderne pc's), of
- **Systeem gereserveerd** (oudere pc's met BIOS / MBR-schijf).

Windows Setup heeft daar minimaal **15 MB vrije ruimte** nodig. Vaak staat de
partitie vol met lettertypebestanden voor het opstartscherm, of met
BIOS-updatebestanden van de fabrikant.

## Oplossing

> ⚠️ Maak eerst een **backup** van je belangrijke bestanden. Je werkt hier met de
> opstartpartitie van Windows.

### Stap 1 – Automatisch controleren en herstellen (aanbevolen)

1. Download [`Fix-SystemReservedPartition.ps1`](Fix-SystemReservedPartition.ps1).
2. Klik met de rechtermuisknop op **Start** en kies **Terminal (Admin)** of
   **Windows PowerShell (Admin)**.
3. Ga naar de map met het script, bijvoorbeeld:

   ```powershell
   cd $env:USERPROFILE\Downloads
   Unblock-File .\Fix-SystemReservedPartition.ps1
   ```

4. **Alleen controleren** (er wordt niets gewijzigd):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Fix-SystemReservedPartition.ps1
   ```

   Je ziet de grootte en de vrije ruimte van de systeempartitie, en de grootste
   bestanden die erop staan.

5. **Ruimte vrijmaken**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Fix-SystemReservedPartition.ps1 -Fix
   ```

   Het script kopieert de lettertypebestanden uit `Boot\Fonts` eerst naar
   `C:\SystemPartitionFontsBackup\<datum-tijd>` en verwijdert ze daarna van de
   systeempartitie. Windows start daarna gewoon op (met het standaardlettertype),
   en Windows Setup zet de bestanden tijdens de upgrade zelf terug.

6. Start de pc opnieuw op en probeer de Windows 11-upgrade opnieuw.

Exitcodes van het script: `0` = in orde, `1` = fout (bijv. niet als Administrator
gestart), `2` = nog te weinig ruimte.

### Stap 2 – Handmatig (als je het script niet wilt gebruiken)

Dit zijn de stappen uit Microsoft-artikel
[KB4051701](https://support.microsoft.com/help/4051701).

**UEFI / GPT** (controleer in **Schijfbeheer**: staat er een *EFI-systeempartitie*?).
Open een **Opdrachtprompt als administrator**:

```cmd
mountvol Y: /s
Y:
cd EFI\Microsoft\Boot\Fonts
del *.*
C:
mountvol Y: /d
```

**BIOS / MBR** (partitie *Systeem gereserveerd*):

1. Open **Schijfbeheer** (`Windows-toets + X` → *Schijfbeheer*).
2. Klik met rechts op **Systeem gereserveerd** → *Stationsletter en paden
   wijzigen* → *Toevoegen* → kies **Y**.
3. Open een **Opdrachtprompt als administrator**:

   ```cmd
   Y:
   cd Boot\Fonts
   takeown /f * /a
   icacls * /grant *S-1-5-32-544:F
   del *.*
   ```

4. Verwijder in Schijfbeheer de stationsletter **Y** weer.

### Stap 3 – Bestanden van de fabrikant opruimen

Toont het script bij *Grootste bestanden* mappen zoals `EFI\HP`, `EFI\Dell` of
`EFI\Lenovo` met BIOS-updatebestanden (`*.bin`, `*.cap`, `*.s12`)? Die zijn vaak
achtergebleven na een BIOS-update. Verwijder deze **alleen** als je zeker weet dat
ze niet meer nodig zijn (raadpleeg de support-site van je fabrikant). Verwijder
**nooit** `EFI\Microsoft\Boot\bootmgfw.efi` of `EFI\Boot\bootx64.efi`.

### Stap 4 – Partitie vergroten (als stap 1–3 niet genoeg is)

Is de systeempartitie erg klein (bijvoorbeeld 100 MB of minder), dan kan het
nodig zijn om de partitie te vergroten. Schijfbeheer van Windows kan dit meestal
niet; gebruik hiervoor een partitietool (bijv. MiniTool Partition Wizard, AOMEI
Partition Assistant). Maak eerst een volledige backup — een fout hierbij kan de pc
onopstartbaar maken. Laat dit bij twijfel door iemand met ervaring doen.

### Stap 5 – Andere aandachtspunten

- Installeer eerst alle Windows-updates en voer **Schijfopruiming** uit.
- Probeer de upgrade via de
  [Windows 11-installatieassistent](https://www.microsoft.com/nl-nl/software-download/windows11)
  of via een gekoppelde ISO (`setup.exe`).
- Controleer met de app **PC-statuscontrole** of je pc aan de systeemeisen van
  Windows 11 voldoet (TPM 2.0, Secure Boot, ondersteunde processor).
