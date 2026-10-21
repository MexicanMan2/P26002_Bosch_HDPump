(********************************************************************************
 * PROGRAM: PRG_RPM_Control_1ms
 * 
 * Beschreibung:
 *   Hauptprogramm für die Motoransteuerung im 1-ms-Echtzeittask.
 *   - Umschaltbar zwischen:
 *       0 = Dreiecksprofil (FB_TriangleProfile)
 *       1 = Sinusprofil mit Phasenversatz (FB_SineProfile)
 *       2 = 10-ms-OPC-UA-Profil (FB_ArrayProfile)
 *   - Sequenzüberwachung mit Zähler- und 48h-Zeitabschaltung
 *   - bSequenceActiveOut (Start/End-Signal) & bLapTriggerOut (gepulst)
 *   - Profibus-Telegrammausgabe an den Frequenzumrichter
 ********************************************************************************)
PROGRAM PRG_RPM_Control_1ms
VAR
    (* --- Globaler Datenspeicher fuer freies Profil (OPC UA beschreibbar) --- *)
    aLapData            : ARRAY[0..179999] OF REAL;
    stOpcUa             : ST_OpcUaInterface;

    (* --- Konfiguration --- *)
    eSelectedProfile    : E_ProfileType     := PROFILE_TRIANGLE;
    stTriangleCfg       : ST_TriangleConfig;
    stSineCfg           : ST_SineConfig;
    eEndMode            : E_SequenceEndMode := MODE_TIME_LIMIT;
    nLapsPreset         : UDINT             := 1000;
    tDurationPreset     : TIME              := T#48h;
    tLapPulseLen        : TIME              := T#50ms;

    (* --- Bedienung & Status --- *)
    bCmdStart           : BOOL;
    bCmdStop            : BOOL;
    bSequenceActiveOut  : BOOL;
    bLapTriggerOut      : BOOL;

    (* --- Baustein-Instanzen --- *)
    fbSeq               : FB_SequenceController;
    fbTriangle          : FB_TriangleProfile;
    fbSine              : FB_SineProfile;
    fbArrayPlayer       : FB_ArrayProfile;
    fbDrive             : FB_ProfibusDrive;

    (* --- Interne Signale --- *)
    fCurrentRpm         : REAL;
    bLapSignal          : BOOL;

    (* --- I/O Mapping fuer Profibus-Master --- *)
    q_Profibus_STW1     AT %Q* : WORD;
    q_Profibus_NSOLL    AT %Q* : INT;
END_VAR

(* 1. Profilberechnung je nach Auswahl *)
CASE eSelectedProfile OF
    PROFILE_TRIANGLE:
        fbTriangle(
            bExecute     := fbSeq.bSequenceActive,
            stConfig     := stTriangleCfg,
            tCycleTime   := T#1ms,
            fRpmOut      => fCurrentRpm,
            bLapFinished => bLapSignal
        );

    PROFILE_SINE:
        fbSine(
            bExecute     := fbSeq.bSequenceActive,
            stConfig     := stSineCfg,
            tCycleTime   := T#1ms,
            fRpmOut      => fCurrentRpm,
            bLapFinished => bLapSignal
        );

    PROFILE_ARRAY_10MS:
        fbArrayPlayer(
            bExecute       := fbSeq.bSequenceActive,
            nPointsInLap   := stOpcUa.nPointsCount,
            aLapDataBuffer := aLapData,
            fRpmOut        => fCurrentRpm,
            bLapFinished   => bLapSignal
        );
END_CASE;

(* 2. Sequenz-Controller *)
fbSeq(
    bStart              := bCmdStart,
    bStop               := bCmdStop,
    eEndMode            := eEndMode,
    nTargetLaps         := nLapsPreset,
    tTargetDuration     := tDurationPreset,
    tLapPulseDuration   := tLapPulseLen,
    bLapFinishedSignal  := bLapSignal,
    tCycleTime          := T#1ms,
    bSequenceActive     => bSequenceActiveOut,
    bLapTrigger         => bLapTriggerOut
);

(* 3. Ausgabe an Frequenzumrichter *)
fbDrive(
    bEnable        := fbSeq.bSequenceActive,
    fRpmSetpoint   := fCurrentRpm,
    fReferenceRpm  := 3000.0,
    nControlWord   => q_Profibus_STW1,
    nSpeedSetpoint => q_Profibus_NSOLL
);

END_PROGRAM
