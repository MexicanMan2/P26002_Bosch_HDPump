# Handbuch: CAN-Raw Kommunikation an Bachmann M1 Steuerungen

Dieses Handbuch beschreibt die Einrichtung, Architektur und den Betrieb der modularen CAN-Raw Kommunikation an Bachmann M1 Steuerungen (z. B. MX207 / MC-Serie) zur Anbindung externer Steuergeräte und Sensoren (z. B. Bosch Motorsport MS7 Logger / ECU).

---

## 1. Hardware- und System-Einrichtung (Bachmann SolutionCenter)

### 1.1 Physikalische Verdrahtung & Bus-Topologie
* **Steckerbelegung (Standard Sub-D 9 Polig bei Bachmann M1):**
  * **Pin 2:** `CAN_L` (CAN Low)
  * **Pin 7:** `CAN_H` (CAN High)
  * **Pin 3 / 6:** `CAN_GND` (Masse / Bezugspotenzial)
  * **Gehäuse:** Schirmung (PE)
* **Bus-Terminierung:**
  * Ein CAN-Bus benötigt zwingend an **beiden physikalischen Enden** jeweils einen **120 $\Omega$ Abschlusswiderstand** zwischen `CAN_H` und `CAN_L`.
  * *Wichtig für MS7:* Laut Konfiguration (`image001.png`) ist der interne Terminierungswiderstand im Bosch MS7 Logger deaktiviert (`Resistor = unchecked`). Stellen Sie sicher, dass am Leitungsende ein 120-$\Omega$-Widerstand geschaltet ist.
* **Baudrate:** 
  * Der Bosch MS7 Logger arbeitet mit **1 Mbit/s (1.000 kBaud)** auf CAN Bus 1.

---

### 1.2 Ermittlung der Hardware-Parameter (CardNb, Chan, NetNb)
In Bachmann M-PLC erfolgt der Treiberzugriff über drei Koordinaten:

1. **`CardNb` (Steckplatz der Baugruppe):**
   * Bezeichnet den physischen Slot im Baugruppenträger (Rack).
   * Bei Kompakt-CPUs (z. B. MX207) ist die CPU meistens **Slot 2** $\rightarrow$ `CardNb := 2`.
   * Bei einer separaten CAN-Karte (z. B. `CAN202`) tragen Sie die Slotnummer ein, auf der die Karte im Rack gesteckt ist.
2. **`Chan` (Schnittstellenkanal):**
   * Bezeichnet den CAN-Port auf der Karte:
     * Port `CAN A` $\rightarrow$ `Chan := 0`
     * Port `CAN B` $\rightarrow$ `Chan := 1`
3. **`NetNb` (Logische Netzwerk-Nummer):**
   * Weist dem Kanal eine interne logische Netzwerk-ID zu (im Standard: `NetNb := 1`).

---

### 1.3 Treiber-Aktivierung im SolutionCenter (`MCONFIG.INI`)
Der Treiber **CUL** (CAN Universal Layer) muss auf der Bachmann-Steuerung geladen sein:

1. Öffnen Sie das Projekt im **Bachmann SolutionCenter**.
2. Prüfen Sie unter **Device Configuration** $\rightarrow$ **Software Configuration** (bzw. in der Datei `MCONFIG.INI`), dass das Modul geladen ist:
   ```ini
   [MODULE]
   CUL.M ; CAN Universal Layer Treiber
   ```
3. Konfigurieren Sie die Baudrate für den entsprechenden CAN-Port auf **1000 kBaud** (1 MBaud).
4. Nach Änderungen Konfiguration auf die Steuerung übertragen und Steuerung neu starten (Reboot).

---

### 1.4 Task-Konfiguration (Laufzeitumgebung)
* **Empfohlene Task-Zykluszeit:** **10 ms bis 20 ms** (zyklische Task, Standardpriorität).
* **Warum nicht 100 ms (wie der Bustakt)?**
  1. **Schwebung / Jitter:** Externe Sender und die SPS laufen nie phasenstarr synchron. Ein schnellerer SPS-Takt verhindert Telegrammverluste und Schwebungen.
  2. **Hardware-Queue:** Die Bachmann CAN-Empfangsqueue wird bei 10–20 ms in jedem Zyklus sofort geleert (`rxCount`), wodurch Buffer-Overflows ausgeschlossen sind.
  3. **Minimale Latenz:** Neue Messwerte stehen der SPS sofort nach Eintreffen zur Verfügung.

---

## 2. Zwingend erforderliche Dateien & Projektstruktur

Für die vollständige CAN-Kommunikation werden genau **4 Dateien** in Ihrem SolutionCenter-Projekt benötigt:

```
ST_CODE_GENERATION/
├── ST_CAN_Broker_Channel.dt    [1. Datentyp: Struktur eines CAN-Kanals]
├── FB_CAN_Broker_Modular.st    [2. Hardware-Treiber: Zentraler CAN-Broker]
├── FB_CAN_Signal.st            [3. Signalebene: Bitgenauer Decoder/Encoder]
└── PRG_MS7_CAN_Handler.st      [4. Applikation: SPS-Hauptprogramm]
```

Zusätzlich muss im SolutionCenter die Bachmann-Systembibliothek **`cul_plc.lib`** eingebunden sein.

---

### 2.1 Datei 1: `ST_CAN_Broker_Channel.dt` (Datentyp)
Kapselt ein einzelnes CAN-Telegramm für Empfang (Rx) und Senden (Tx):
* **`RxCobId`:** Empfangs-CAN-ID (z. B. `16#650`).
* **`RxData`:** 8-Byte Nutzdatenfeld der empfangenen Botschaft.
* **`RxNew`:** Flanke für genau einen Zyklus, wenn ein neues Telegramm eingetroffen ist.
* **`TxCobId`:** Sende-CAN-ID (z. B. `16#680`).
* **`TxData`:** 8-Byte Nutzdatenfeld, das auf den Bus gesendet werden soll.
* **`TxReq`:** Sendeauftrag anfordern (`TRUE`).
* **`TxBusy` / `TxDone` / `TxError`:** Rückmeldungen des Sende-Schedulers.

---

### 2.2 Datei 2: `FB_CAN_Broker_Modular.st` (Hardware-Broker)
Der zentrale Treiber-Baustein:
* Verwaltet bis zu **32 Kanäle** in einem einzigen Array (`Channels : ARRAY [1..32] OF ST_CAN_Broker_Channel`).
* Schaltet über `Cul_EnableMsg` alle konfigurierten `RxCobId`s beim Hardware-Controller frei.
* Leert in jedem Zyklus per `CUL_ReceiveMsg` die Empfangsqueue und verteilt die Daten blitzschnell auf den passenden Kanal.
* Verwaltet Sendeaufträge per nicht-blockierendem **Round-Robin** (`CUL_SendMsg_NB`), wodurch Kollisionen auf dem Bus ausgeschlossen sind.
* Über den Parameter **`NumChannels`** sagen Sie dem Broker, wie viele Kanäle aktiv sind (z. B. `5`).

---

### 2.3 Datei 3: `FB_CAN_Signal.st` (Signal-Decoder & Encoder)
Universeller Baustein für Messwerte und Stellwerte:
* **Format:** Ausgelegt für **Little-Endian (Intel)** gemäß Bosch Motorsport / RaceCon V2.x.
* **Flexibilität:** Unterstützt beliebige Bitlängen (1 bis 32 Bit) und Start-Bits (0 bis 63).
* **Read-Modify-Write:** Beim Schreiben werden nur die definierten Bits verändert; fremde Nachbarbits im selben Byte bleiben unberührt.
* **Bachmann-Kompatibilität:** Verwendet strikt konforme Typkonvertierungen (`BYTE_TO_DWORD`, `DWORD_TO_BYTE`, `DINT_TO_REAL`, etc.).
* **Physikalische Skalierung:** $\text{PhysValue} = (\text{Raw} \cdot \text{Factor}) + \text{Offset}$.

---

### 2.4 Datei 4: `PRG_MS7_CAN_Handler.st` (Anwendungsprogramm)
Das vollständige Programm für das Bosch MS7 Netzwerk mit 12 Kanälen:
1. Richtet die 12 Botschaften in der Maske `canChannels` ein:
   * **Empfangskanäle (R / Rx):**
     * **Kanal 1 (Rx):** ID `16#650` (`prail_nom`, `tfuel`, `toil`, `prail_650`)
     * **Kanal 2 (Rx):** ID `16#660` (`msv_divy_angle`, `angle_eng_hdp_meas`, `tinj`, `prail_660`)
     * **Kanal 3 (Rx):** ID `16#670` (`tEKP`, `pEKP`, `pfuel`)
     * **Kanal 4 (Rx):** ID `16#456` (`tecu_cpu`)
     * **Kanal 5 (Rx):** ID `16#680` (`Drehzahl / RPM`)
   * **Sendekanäle (W / Tx):**
     * **Kanal 6  (Tx):** ID `16#700` (`Set RPM`, `Actual RPM`, `valid RPM`)
     * **Kanal 7  (Tx):** ID `16#710` (`Oil pressure`, `Oil temperature`, `OK-Bits`)
     * **Kanal 8  (Tx):** ID `16#720` (`Fuel temp`, `Fuel supply press`, `OK-Bits`)
     * **Kanal 9  (Tx):** ID `16#730` (`Fuel Mass Flow 1, 2, 3`, `valid Bit`)
     * **Kanal 10 (Tx):** ID `16#800` (`ERROR_Bits`)
     * **Kanal 11 (Tx):** ID `16#900` (`Counter LAP`, `Counter FREE TRIGGER`)
     * **Kanal 12 (Tx):** ID `16#910` (`RPM Profile (reserviert)`)
2. Ruft den modularen Broker mit `NumChannels := 12` auf.
3. Überträgt alle Messwerte in lokale `REAL`-Variablen (`rTecu_cpu`, `rEngine_RPM`, `rPrail_nom`, etc.).
4. Sendet alle 100 ms (jeden 10. SPS-Durchlauf bei 10 ms Task) die Schreibtelegramme per Round-Robin.

---

## 3. Schritt-für-Schritt Inbetriebnahme

1. **Dateien ins SolutionCenter-Projekt kopieren:**
   * Kopieren Sie die 4 Dateien in Ihr M-PLC Quellcode-Verzeichnis.
2. **Bibliothek prüfen:**
   * Stellen Sie sicher, dass `cul_plc.lib` in der Bibliotheksverwaltung des Projekts referenziert ist.
3. **Task zuweisen:**
   * Öffnen Sie die Task-Konfiguration im SolutionCenter.
   * Weisen Sie `PRG_MS7_CAN_Handler` einer zyklischen Task mit **10 ms oder 20 ms** Zykluszeit zu.
4. **Kompilieren & Übertragen:**
   * Projekt fehlerfrei kompilieren.
   * Auf die Bachmann CPU laden und starten.
5. **Diagnose & Beobachten:**
   * Öffnen Sie das **Watch-Fenster**:
     * `bBrokerReady` muss `TRUE` sein.
     * `bBrokerError` muss `FALSE` sein.
     * Beobachten Sie die Variablen `rPrail_650`, `rTfuel`, `rTekp` etc. – sie aktualisieren sich nun alle 100 ms live!

---

## 4. Software-Verknüpfung im SolutionCenter (Architektur & Datenfluss)

### 4.1 Die 3 Schichten der Software-Architektur

```
   ┌────────────────────────────────────────────────────────┐
   │ Schicht 1: Hardware-Treiber (FB_CAN_Broker_Modular)    │
   │  - Liest HW-Queue aus (CUL_ReceiveMsg)                 │
   │  - Schreibt HW-Sendequeue (CUL_SendMsg_NB)             │
   └───────────────────────────┬────────────────────────────┘
                               │ canChannels[1..32]
   ┌───────────────────────────▼────────────────────────────┐
   │ Schicht 2: Botschaftsebene (ST_CAN_Broker_Channel)     │
   │  - Puffer für 8 Bytes Daten (RxData / TxData)          │
   │  - Flanken & Status (RxNew, TxReq, TxBusy)             │
   └───────────────────────────┬────────────────────────────┘
                               │ Data := canChannels[x].RxData
   ┌───────────────────────────▼────────────────────────────┐
   │ Schicht 3: Signalebene (FB_CAN_Signal)                 │
   │  - Bitgenaue Extraktion / Einbettung                   │
   │  - Skalierung: Raw <---> PhysValue (REAL)              │
   └───────────────────────────┬────────────────────────────┘
                               │ rPrail_nom, rToil, rTekp ...
   ┌───────────────────────────▼────────────────────────────┐
   │ Schicht 4: Ihre Steuerungslogik / Hauptprogramm        │
   │  - Regelung, Grenzwerte, HMI / Visu                    │
   └────────────────────────────────────────────────────────┘
```

### 4.2 Wie Daten für andere Programmteile bereitgestellt werden (GVL)

Wenn andere Programme oder FBs (z. B. Ihre Hauptsteuerung oder Visu) auf die MS7-Werte zugreifen sollen, empfiehlt sich eine **Globale Variablenliste (GVL)**:

```pascal
VAR_GLOBAL
    g_MS7_Prail       : REAL; (* Raildruck Istwert *)
    g_MS7_Toil        : REAL; (* Öltemperatur *)
    g_MS7_Tfuel       : REAL; (* Kraftstofftemperatur *)
    g_MS7_Cmd_Start   : BOOL; (* Start-Befehl an MS7 *)
    g_MS7_Cmd_Setp    : REAL; (* Sollwert an MS7 *)
END_VAR
```

In `PRG_MS7_CAN_Handler` weisen Sie die Messwerte am Zyklusende einfach zu:
```pascal
g_MS7_Prail := rPrail_650;
g_MS7_Toil  := rToil;
g_MS7_Tfuel := rTfuel;
```
Und beim Schreiben übernehmen Sie die Werte aus der GVL:
```pascal
rWrite_Setpoint := g_MS7_Cmd_Setp;
bWrite_Start    := g_MS7_Cmd_Start;
```
