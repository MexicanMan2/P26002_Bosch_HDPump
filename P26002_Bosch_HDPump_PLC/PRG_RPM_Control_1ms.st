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


    (* --- Konfiguration --- *)
    fRampAccelPreset    : REAL              := 500.0; (* U/s Beschleunigung *)

    (* --- Bedienung & Status --- *)
    bLapTriggerOut      : BOOL;
    fTargetRpm			: REAL;
    bCmdResetDrive      : BOOL;
    bDriveReadyOut      : BOOL;
    bDriveErrorOut      : BOOL;

    (* --- Baustein-Instanzen --- *)
    fbSeq               : FB_SequenceController;
    fbTriangle          : FB_TriangleProfile;
    fbSine              : FB_SineProfile;
    fbArrayPlayer       : FB_ArrayProfile;
    fbDrive             : FB_ProfibusDrive;

    (* --- Interne Signale --- *)
    fCurrentRpm         : REAL;
    fActualRpmNW        : REAL;
    bLapSignal          : BOOL;

    (* --- PROFINET / PROFIBUS I/O Mapping (Slot 4: SEW MOVIAXIS) --- *)
    (* Ausgänge an Umrichter (PA 1..4 = 8 Byte) *)
(*     q_SEW_Action        AT %Q* : INT;   (* PA 1: Aktion (20 = Linkslauf, 32 = Reset, 0 = Stopp) *) *)
(*     q_SEW_SpeedSetpoint AT %Q* : INT;   (* PA 2: Motordrehzahl = Nockenwellendrehzahl / 1.43 *) *)
(*     q_SEW_Accel         AT %Q* : INT;   (* PA 3: Beschleunigung [U/s] *) *)
(*     q_SEW_Ruck          AT %Q* : INT;   (* PA 4: Ruck (fest 0) *) *)
(*  *)
(*     (* Eingänge von Umrichter (PE 1..4 = 8 Byte) *) *)
(*     i_SEW_StatusWord    AT %I* : WORD;  (* PE 1: Statuswort Umrichter *) *)
(*     i_SEW_ActualSpeed   AT %I* : INT;   (* PE 2: Motor-Istdrehzahl *) *)
(*     i_SEW_ActualCurrent AT %I* : INT;   (* PE 3: Motorstrom *) *)
(*     i_SEW_DiagInfo      AT %I* : WORD;  (* PE 4: Diagnose / Fehlercode *) *)
END_VAR

(* 1. Profilberechnung je nach Auswahl *)
CASE AutomaticOperation.current_OP.ProfileType OF
    PROFILE_TRIANGLE:
        fbTriangle(
            bExecute     := fbSeq.bSequenceActive,
            stConfig     := AutomaticOperation.current_OP.ProfileConfig.TriangleConfig,
            tCycleTime   := T#1ms,
            fRpmOut      => fCurrentRpm,
            bLapFinished => bLapSignal
        );

    PROFILE_SINE:
        fbSine(
            bExecute     := fbSeq.bSequenceActive,
            stConfig     := AutomaticOperation.current_OP.ProfileConfig.SineConfig,
            tCycleTime   := T#1ms,
            fRpmOut      => fCurrentRpm,
            bLapFinished => bLapSignal
        );

    PROFILE_ARRAY_10MS:
        fbArrayPlayer(
            bExecute       := fbSeq.bSequenceActive,
            nPointsInLap   := AutomaticOperation.current_OP.ProfileConfig.FreeConfig.nPointsCount,
            aLapDataBuffer := AutomaticOperation.current_OP.ProfileConfig.FreeConfig.LapData,
            fRpmOut        => fCurrentRpm,
            bLapFinished   => bLapSignal
        );
END_CASE;

(* 2. Sequenz-Controller *)
fbSeq(
    bStart              := AutomaticOperation.start_sequence,
    bStop               := AutomaticOperation.stop_sequence,
    eEndMode            := AutomaticOperation.current_OP.ProfileConfig.eEndMode,
    nTargetLaps         := AutomaticOperation.current_OP.ProfileConfig.nLaps,
    tTargetDuration     := AutomaticOperation.current_OP.ProfileConfig.tDuration,
    tLapPulseDuration   := User.Settings.tLapPulseLen,
    bLapFinishedSignal  := bLapSignal,
    tCycleTime          := T#1ms,
    bSequenceActive     => AutomaticOperation.sequence_active,
    bLapTrigger         => bLapTriggerOut,
    nCompletedLaps      => User.Output.nActualLaps,       (* <- HIER: Rundenanzahl abholen *)
    tElapsedTime        => User.Output.tActualTime        (* <- HIER: Bisherige Laufzeit abholen *)
);


(* 3. Ausgabe an Frequenzumrichter *)
IF AutomaticOperation.State = OP_PREP THEN
	fTargetRpm := AutomaticOperation.coldStart_RPM;
	fbDrive.bEnable := TRUE;
ELSIF fbSeq.bSequenceActive THEN
	fTargetRpm := fCurrentRpm;
	fbDrive.bEnable := TRUE;
ELSE (* Wenn Sequenz AUS ist: Solldrehzahl GARANTIERT auf 0.0 zwingen! *)
	fTargetRpm := 0.0;
	fbDrive.bEnable := FALSE;
END_IF

fbDrive(
    bReset              := bCmdResetDrive,
    bDirectionReverse   := FALSE, (* FALSE = Linkslauf (HDP-Standard) *)
    fRpmSetpoint   		:= fTargetRpm,
    fRampAccel          := fRampAccelPreset,
    fGearRatio          := 1.43,
(*     i_nStatusWord       := i_SEW_StatusWord, *)
(*     i_nActualSpeed      := i_SEW_ActualSpeed, *)
(*     i_nActualCurrent    := i_SEW_ActualCurrent, *)
(*     i_nDiagInfo         := i_SEW_DiagInfo, *)
(*     q_nActionCode       => q_SEW_Action, *)
(*     q_nSpeedSetpoint    => q_SEW_SpeedSetpoint, *)
(*     q_nRampAccel        => q_SEW_Accel, *)
(*     q_nRuck             => q_SEW_Ruck, *)
    rActualRpmNW        => fActualRpmNW,
    bDriveReady         => bDriveReadyOut,
    bDriveError         => bDriveErrorOut
);


END_PROGRAM
