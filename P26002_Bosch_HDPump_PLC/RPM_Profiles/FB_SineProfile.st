(********************************************************************************
 * FUNCTION_BLOCK: FB_SineProfile
 * 
 * Beschreibung:
 *   Erzeugt im 1-ms-Takt ein Sinus-Drehzahlprofil zwischen fRpmMin und fRpmMax
 *   mit parametrierbarer Periodendauer und Phasenversatz in Grad.
 *   Am Ende jeder Periode (tPeriod) wird bLapFinished fuer einen Takt TRUE.
 ********************************************************************************)
FUNCTION_BLOCK FB_SineProfile
VAR_INPUT
    bExecute        : BOOL;
    stConfig        : ST_SineConfig;
    tCycleTime      : TIME := T#1ms;
END_VAR
VAR_OUTPUT
    fRpmOut         : REAL;
    bLapFinished    : BOOL;
END_VAR
VAR
    tCurrentLapTime : TIME := T#0s;
    fOffset         : REAL;
    fAmplitude      : REAL;
    fPeriodSec      : REAL;
    fCurSec         : REAL;
    fPhaseRad       : REAL;
    fAngleRad       : REAL;
END_VAR
VAR CONSTANT
    C_PI            : REAL := 3.14159265;
    C_DEG_TO_RAD    : REAL := 0.0174532925; (* PI / 180.0 *)
END_VAR

bLapFinished := FALSE;

IF NOT bExecute THEN
    tCurrentLapTime := T#0s;
    fRpmOut         := stConfig.fRpmMin;
    RETURN;
END_IF;

fPeriodSec := TIME_TO_REAL(stConfig.tPeriod) / 1000.0;
fCurSec    := TIME_TO_REAL(tCurrentLapTime) / 1000.0;

(* Schutz vor Division durch 0 *)
IF fPeriodSec <= 0.0 THEN
    fRpmOut := stConfig.fRpmMin;
    RETURN;
END_IF;

(* 1. Mittelwert (Offset) und Amplitude berechnen *)
fOffset    := (stConfig.fRpmMax + stConfig.fRpmMin) / 2.0;
fAmplitude := (stConfig.fRpmMax - stConfig.fRpmMin) / 2.0;

(* 2. Phasenversatz und aktuellen Winkel in Bogenmass berechnen *)
fPhaseRad := stConfig.fPhaseDeg * C_DEG_TO_RAD;
fAngleRad := ((2.0 * C_PI / fPeriodSec) * fCurSec) + fPhaseRad;

(* 3. Sollwert ueber Standard-IEC SIN-Funktion berechnen *)
fRpmOut := fOffset + (fAmplitude * SIN(fAngleRad));

(* 4. Zeittakt weiterschalten (1 ms) *)
tCurrentLapTime := tCurrentLapTime + tCycleTime;

(* 5. Periodenende (Lap) erkennen *)
IF tCurrentLapTime >= stConfig.tPeriod THEN
    tCurrentLapTime := T#0s;
    bLapFinished    := TRUE;
END_IF;

END_FUNCTION_BLOCK
