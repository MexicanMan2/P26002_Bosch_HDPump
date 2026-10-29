(********************************************************************************
 * FUNCTION_BLOCK: FB_ProfibusDrive
 * 
 * Beschreibung:
 *   Ansteuerung des SEW MOVIAXIS Servoverstärkers über das ADFweb 
 *   PROFINET/PROFIBUS Gateway HD67604-A1 (GSD: SEW_6006.GSD, Modul: 4 PD / 4 Worte).
 * 
 *   Sollwert-Telegramm (SPS -> Umrichter, 8 Byte / 4 Worte):
 *     - PA 1 (Word 0): nActionCode (20 = Linkslauf HDP, 12 = Rechtslauf, 32 = Reset, 0 = Stopp)
 *     - PA 2 (Word 1): nSpeedSetpoint (Motordrehzahl = Nockenwellendrehzahl / 1.43)
 *     - PA 3 (Word 2): nRampAccel (Beschleunigungsvorgabe in U/s, Standard 500)
 *     - PA 4 (Word 3): nRuck (fest 0)
 * 
 *   Istwert-Telegramm (Umrichter -> SPS, 8 Byte / 4 Worte):
 *     - PE 1 (Word 0): nStatusWord (Statuswort des Umrichters)
 *     - PE 2 (Word 1): nActualSpeed (Motor-Istdrehzahl; NW-Drehzahl = nActualSpeed * 1.43)
 *     - PE 3 (Word 2): nActualCurrent (Motorstrom / Last)
 *     - PE 4 (Word 3): nDiagInfo (Fehler / Diagnose)
 ********************************************************************************)
FUNCTION_BLOCK FB_ProfibusDrive
VAR_INPUT
    bEnable             : BOOL := FALSE;    (* Antriebsfreigabe *)
    bReset              : BOOL := FALSE;    (* Störungsquittierung / Reset (Aktion 32) *)
    bDirectionReverse   : BOOL := FALSE;    (* FALSE = Linkslauf (Standard HDP, Code 20), TRUE = Rechtslauf (Code 12) *)
    fRpmSetpoint        : REAL := 0.0;      (* Solldrehzahl an der Nockenwelle [U/min] *)
    fRampAccel          : REAL := 500.0;    (* Beschleunigung [U/s] (Standard 500, min 30) *)
    fGearRatio          : REAL := 1.43;     (* Übersetzungsverhältnis Getriebe (Motor : NW = 1 : 1.43) *)

    (* --- Eingangsdaten von Umrichter (8 Byte / 4 Worte) --- *)
    i_nStatusWord       : WORD := 16#0000;  (* PE 1: Statuswort *)
    i_nActualSpeed      : INT  := 0;        (* PE 2: Motoristdrehzahl [U/min] *)
    i_nActualCurrent    : INT  := 0;        (* PE 3: Motorstrom *)
    i_nDiagInfo         : WORD := 16#0000;  (* PE 4: Diagnose / Fehlercode *)
END_VAR

VAR_OUTPUT
    (* --- Ausgangsdaten an Umrichter (8 Byte / 4 Worte) --- *)
    q_nActionCode       : INT  := 0;        (* PA 1: Aktion (20, 12, 32, 0) *)
    q_nSpeedSetpoint    : INT  := 0;        (* PA 2: Motordrehzahl [U/min] *)
    q_nRampAccel        : INT  := 500;      (* PA 3: Beschleunigung [U/s] *)
    q_nRuck             : INT  := 0;        (* PA 4: Ruck (immer 0) *)

    (* --- Berechnete Prozesswerte für Applikation --- *)
    rActualRpmNW        : REAL := 0.0;      (* Rückgerechnete Nockenwellendrehzahl [U/min] *)
    rActualRpmMotor     : REAL := 0.0;      (* Motoristdrehzahl [U/min] *)
    bDriveReady         : BOOL := FALSE;    (* Umrichter betriebsbereit *)
    bDriveError         : BOOL := FALSE;    (* Umrichter meldet Störung *)
END_VAR

VAR
    fMotorRpmCalc       : REAL;
    fAccelCalc          : REAL;
END_VAR

(* 1. Fehler- und Statusauswertung *)
bDriveReady := (i_nStatusWord AND 16#0001) <> 16#0000;
bDriveError := (i_nStatusWord AND 16#0002) <> 16#0000;

(* Rückrechnung der Istdrehzahl auf Nockenwelle *)
rActualRpmMotor := INT_TO_REAL(i_nActualSpeed);
IF fGearRatio > 0.0 THEN
    rActualRpmNW := rActualRpmMotor * fGearRatio;
ELSE
    rActualRpmNW := rActualRpmMotor;
END_IF;

(* 2. Steuerwort / Aktion festlegen *)
IF bReset THEN
    (* Code 32: Reset des Frequenzumrichters *)
    q_nActionCode    := 32;
    q_nSpeedSetpoint := 0;
    q_nRampAccel     := 500;
    q_nRuck          := 0;

ELSIF bEnable THEN
    (* Code 20 = Linkslauf (HDP Standard), Code 12 = Rechtslauf *)
    IF bDirectionReverse THEN
        q_nActionCode := 12;
    ELSE
        q_nActionCode := 20;
    END_IF;

    (* Drehzahlsollwert für Motor berechnen: n_Motor = n_NW / 1.43 *)
    IF fGearRatio > 0.0 THEN
        fMotorRpmCalc := fRpmSetpoint / fGearRatio;
    ELSE
        fMotorRpmCalc := fRpmSetpoint;
    END_IF;

    (* Begrenzung Motor-Drehzahl auf Grenzwerte (max 15000 U/min) *)
    IF fMotorRpmCalc > 15000.0 THEN
        fMotorRpmCalc := 15000.0;
    ELSIF fMotorRpmCalc < 0.0 THEN
        fMotorRpmCalc := 0.0;
    END_IF;
    q_nSpeedSetpoint := REAL_TO_INT(fMotorRpmCalc);

    (* Beschleunigung begrenzen (min 30 U/s) *)
    fAccelCalc := fRampAccel;
    IF fAccelCalc < 30.0 THEN
        fAccelCalc := 30.0;
    ELSIF fAccelCalc > 2000.0 THEN
        fAccelCalc := 2000.0;
    END_IF;
    q_nRampAccel := REAL_TO_INT(fAccelCalc);

    (* Ruck immer 0 *)
    q_nRuck := 0;

ELSE
    (* Stillstand / Stopp *)
    q_nActionCode    := 0;
    q_nSpeedSetpoint := 0;
    q_nRampAccel     := 500;
    q_nRuck          := 0;
END_IF;

END_FUNCTION_BLOCK
