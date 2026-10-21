(********************************************************************************
 * FUNCTION_BLOCK: FB_TriangleProfile
 * 
 * Beschreibung:
 *   Erzeugt im 1-ms-Takt ein symmetrisches oder asymmetrisches Dreiecksprofil
 *   zwischen fRpmMin und fRpmMax.
 *   Am Ende der Rampe wird bLapFinished für genau einen Takt TRUE.
 ********************************************************************************)
FUNCTION_BLOCK FB_TriangleProfile
VAR_INPUT
    bExecute        : BOOL;
    stConfig        : ST_TriangleConfig;
    tCycleTime      : TIME := T#1ms;
END_VAR
VAR_OUTPUT
    fRpmOut         : REAL;
    bLapFinished    : BOOL;
END_VAR
VAR
    tCurrentLapTime : TIME := T#0s;
    tRampDownEff    : TIME;
    tTotalLapTime   : TIME;
    fUpSec          : REAL;
    fDownSec        : REAL;
    fCurSec         : REAL;
    fDeltaRpm       : REAL;
END_VAR

bLapFinished := FALSE;

IF NOT bExecute THEN
    tCurrentLapTime := T#0s;
    fRpmOut         := stConfig.fRpmMin;
    RETURN;
END_IF;

(* 1. Symmetrie auswerten *)
IF stConfig.bSymmetric THEN
    tRampDownEff := stConfig.tRampUp;
ELSE
    tRampDownEff := stConfig.tRampDown;
END_IF;

tTotalLapTime := stConfig.tRampUp + tRampDownEff;
fDeltaRpm     := stConfig.fRpmMax - stConfig.fRpmMin;

fUpSec   := TIME_TO_REAL(stConfig.tRampUp) / 1000.0;
fDownSec := TIME_TO_REAL(tRampDownEff) / 1000.0;
fCurSec  := TIME_TO_REAL(tCurrentLapTime) / 1000.0;

(* 2. Rampe berechnen *)
IF tCurrentLapTime < stConfig.tRampUp THEN
    (* Phase 1: Anstieg von Min nach Max *)
    IF fUpSec > 0.0 THEN
        fRpmOut := stConfig.fRpmMin + (fDeltaRpm * (fCurSec / fUpSec));
    ELSE
        fRpmOut := stConfig.fRpmMax;
    END_IF;
ELSE
    (* Phase 2: Abstieg von Max nach Min *)
    IF fDownSec > 0.0 THEN
        fRpmOut := stConfig.fRpmMax - (fDeltaRpm * ((fCurSec - fUpSec) / fDownSec));
    ELSE
        fRpmOut := stConfig.fRpmMin;
    END_IF;
END_IF;

(* 3. Zeittakt weiterschalten (1 ms) *)
tCurrentLapTime := tCurrentLapTime + tCycleTime;

(* 4. Rundenende prüfen *)
IF tCurrentLapTime >= tTotalLapTime THEN
    tCurrentLapTime := T#0s;
    bLapFinished    := TRUE;
END_IF;

END_FUNCTION_BLOCK
