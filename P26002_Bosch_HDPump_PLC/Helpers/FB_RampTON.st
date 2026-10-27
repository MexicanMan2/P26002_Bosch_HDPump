FUNCTION_BLOCK FB_RampTON
VAR_INPUT
    bExecute        : BOOL;         (* TRUE = Rampe laeuft und haelt Zielwert; FALSE = Reset auf X *)
    fStartVal       : REAL;         (* X *)
    fTargetVal      : REAL;         (* Y *)
    tRampTime       : TIME;         (* t (z.B. T#5s) *)
END_VAR
VAR_OUTPUT
    fCurrentVal     : REAL;         (* Aktueller Wert *)
    bDone           : BOOL;         (* TRUE sobald Y erreicht ist *)
END_VAR
VAR
    fbTimer         : TON;          (* Der Standard-IEC-Timer *)
    fRatio          : REAL;
END_VAR

(* 1. Timer aufrufen: Misst die Zeit automatisch ueber das System *)
fbTimer(IN := bExecute, PT := tRampTime);

(* 2. Rampenlogik *)
IF bExecute THEN

    IF fbTimer.Q THEN
        (* Timer ist abgelaufen: Exakt auf Zielwert Y festnageln *)
        fCurrentVal := fTargetVal;
        bDone       := TRUE;
    ELSE
        (* Timer laeuft noch: Fortschritt ueber .ET (Elapsed Time) berechnen *)
        IF tRampTime > T#0s THEN
            fRatio      := TIME_TO_REAL(fbTimer.ET) / TIME_TO_REAL(tRampTime);
            fCurrentVal := fStartVal + (fTargetVal - fStartVal) * fRatio;
        ELSE
            fCurrentVal := fTargetVal;
        END_IF;
        bDone := FALSE;
    END_IF;

ELSE
    (* Bei bExecute = FALSE: Auf Startwert X zuruecksetzen *)
    fCurrentVal := fStartVal;
    bDone       := FALSE;
END_IF;

END_FUNCTION_BLOCK