(********************************************************************************
 * FUNCTION_BLOCK: FB_ArrayProfile
 * 
 * Beschreibung:
 *   Liest ein 10-ms-Raster Drehzahlprofil aus dem globalen Array aLapData
 *   und interpoliert im 1-ms-Takt stufenlos linear.
 *   Bei Erreichen von nPointsInLap springt der Zeiger auf 0 zurück und
 *   bLapFinished wird für einen Zyklus TRUE.
 ********************************************************************************)
FUNCTION_BLOCK FB_ArrayProfile
VAR_INPUT
    bExecute        : BOOL;
    nPointsInLap    : DINT; (* Tatsächliche Anzahl Punkte im Zyklus *)
END_VAR
VAR_IN_OUT
    aLapDataBuffer  : ARRAY[0..179999] OF REAL; (* Referenz auf das Daten-Array *)
END_VAR
VAR_OUTPUT
    fRpmOut         : REAL;
    bLapFinished    : BOOL;
END_VAR
VAR
    nIndex          : DINT := 0;
    nSubStep1ms     : INT  := 0;
    fCurrentP       : REAL;
    fNextP          : REAL;
    fDeltaPerMs     : REAL;
END_VAR

bLapFinished := FALSE;

(* Plausibilitätsprüfung *)
IF NOT bExecute OR (nPointsInLap <= 1) OR (nPointsInLap > 180000) THEN
    nIndex       := 0;
    nSubStep1ms  := 0;
    fRpmOut      := 0.0;
    RETURN;
END_IF;

(* Alle 10 ms: Neuer Stützwert aus dem Array *)
IF nSubStep1ms = 0 THEN
    fCurrentP := aLapDataBuffer[nIndex];

    (* Nächsten Punkt für Steigungsberechnung holen *)
    IF (nIndex + 1) < nPointsInLap THEN
        fNextP := aLapDataBuffer[nIndex + 1];
    ELSE
        fNextP := aLapDataBuffer[0]; (* Zyklischer Sprung zum Anfang *)
    END_IF;

    (* Steigung pro 1 ms berechnen *)
    fDeltaPerMs := (fNextP - fCurrentP) / 10.0;

    nIndex := nIndex + 1;

    (* RUNDENENDE: Letzter Punkt des Profils erreicht *)
    IF nIndex >= nPointsInLap THEN
        nIndex       := 0;    (* Für nächste Runde zurücksetzen *)
        bLapFinished := TRUE; (* Lap-Signal auslösen *)
    END_IF;
END_IF;

(* 1-ms-Interpolation *)
fRpmOut := fCurrentP + (fDeltaPerMs * INT_TO_REAL(nSubStep1ms));

(* 1-ms-Zähler 0 bis 9 *)
nSubStep1ms := (nSubStep1ms + 1) MOD 10;

END_FUNCTION_BLOCK
