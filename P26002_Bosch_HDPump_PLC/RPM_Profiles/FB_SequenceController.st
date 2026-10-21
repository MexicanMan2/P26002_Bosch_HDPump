(********************************************************************************
 * FUNCTION_BLOCK: FB_SequenceController
 * 
 * Beschreibung:
 *   Steuert den Gesamt-Ablauf (Start/Stop, Wiederholungen, Gesamtdauer).
 *   Ausgänge:
 *     - bSequenceActive: TRUE ab Start bis zum Ende der gesamten Sequenz
 *     - bLapTrigger:     Gepulster Ausgang (z.B. 50ms) nach jedem Lap-Durchlauf
 ********************************************************************************)
FUNCTION_BLOCK FB_SequenceController
VAR_INPUT
    bStart              : BOOL;
    bStop               : BOOL;
    eEndMode            : E_SequenceEndMode;
    nTargetLaps         : UDINT;
    tTargetDuration     : TIME;
    tLapPulseDuration   : TIME := T#50ms; (* Einstellbare Pulsdauer *)
    bLapFinishedSignal  : BOOL;
    tCycleTime          : TIME := T#1ms;
END_VAR
VAR_OUTPUT
    bSequenceActive     : BOOL; (* Start/End-Trigger *)
    bLapTrigger         : BOOL; (* Gepulster Lap-Trigger *)
    nCompletedLaps      : UDINT;
    tElapsedTime        : TIME;
END_VAR
VAR
    bStartOld           : BOOL;
    nPulseCyclesLeft    : DINT := 0; (* Exakter Zyklustimer für den Puls *)
END_VAR

(* Stop-Befehl *)
IF bStop THEN
    bSequenceActive  := FALSE;
    nPulseCyclesLeft := 0;
END_IF;

(* Start-Flanke *)
IF bStart AND NOT bStartOld AND NOT bSequenceActive THEN
    bSequenceActive  := TRUE;
    nCompletedLaps   := 0;
    tElapsedTime     := T#0s;
    nPulseCyclesLeft := 0;
END_IF;
bStartOld := bStart;

(* Sequenz-Ablauf *)
IF bSequenceActive THEN
    tElapsedTime := tElapsedTime + tCycleTime;

    (* Lap-Ende registriert *)
    IF bLapFinishedSignal THEN
        nCompletedLaps   := nCompletedLaps + 1;
        (* Millisekunden in 1ms-Taskzyklen konvertieren *)
        nPulseCyclesLeft := TIME_TO_DINT(tLapPulseDuration);
    END_IF;

    (* Abbruchbedingungen *)
    CASE eEndMode OF
        MODE_LAP_COUNT:
            IF nCompletedLaps >= nTargetLaps THEN
                bSequenceActive := FALSE;
            END_IF;

        MODE_TIME_LIMIT:
            IF tElapsedTime >= tTargetDuration THEN
                bSequenceActive := FALSE;
            END_IF;
    END_CASE;
END_IF;

(* Deterministischer Puls über Zyklencounter *)
IF nPulseCyclesLeft > 0 THEN
    bLapTrigger      := TRUE;
    nPulseCyclesLeft := nPulseCyclesLeft - 1;
ELSE
    bLapTrigger := FALSE;
END_IF;

END_FUNCTION_BLOCK
