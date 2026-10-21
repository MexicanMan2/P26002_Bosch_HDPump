(********************************************************************************
 * PROGRAM: PRG_MS7_CAN_Handler
 * 
 * Beschreibung:
 *   Vollständiges Anwendungsbeispiel für das Auslesen und Schreiben des 
 *   CAN-Netzwerks (Bosch MS7 Logger / ECU) an einer Bachmann M1 Steuerung.
 * 
 *   1. Botschaftsebene (Telegramme):
 *      canChannels : ARRAY [1..32] OF ST_CAN_Broker_Channel
 *      - Kanal 1 (Rx): ID 16#650 (prail_nom, tfuel, toil, prail)
 *      - Kanal 2 (Rx): ID 16#660 (msv_divy_angle, angle_eng_hdp_meas, tinj, prail)
 *      - Kanal 3 (Rx): ID 16#670 (tEKP, pEKP, pfuel)
 *      - Kanal 4 (Rx): ID 16#456 (tecu_cpu)
 *      - Kanal 5 (Tx): ID 16#680 (Multi-Signal Schreibkanal: Modus, Sollwert, Bools)
 * 
 *   2. Hardware-Broker:
 *      FB_CAN_Broker_Modular verarbeitet alle 5 Kanäle dynamisch.
 * 
 *   3. Signalebene:
 *      Alle 12 Messwerte aus image001.png werden zyklisch decodiert und 
 *      in dedizierte lokale REAL-Variablen übertragen.
 *      ID 16#680 demonstriert bitgenaues Packen mehrerer Signale (8 Bit, 16 Bit, Bools).
 ********************************************************************************)
PROGRAM PRG_MS7_CAN_Handler
VAR
    (* ======================================================================== *)
    (* 1. Konfigurationstabelle / Maske aller CAN-Kanäle (Botschaftsebene)      *)
    (* ======================================================================== *)
    canChannels         : ARRAY [1..32] OF ST_CAN_Broker_Channel;
    bConfigDone         : BOOL := FALSE;

    (* Hardware CAN-Broker Instanz (modular bis 32 Kanäle) *)
    fbBroker            : FB_CAN_Broker_Modular;
    bBrokerReady        : BOOL;
    bBrokerError        : BOOL;
    nBrokerErrorID      : DINT;

    (* ======================================================================== *)
    (* 2. Signal-Instanzen zum LESEN laut image001.png                         *)
    (* ======================================================================== *)
    (* Kanal 4: Botschaft 16#456 *)
    fb_tecu_cpu         : FB_CAN_Signal;

    (* Kanal 1: Botschaft 16#650 *)
    fb_prail_nom        : FB_CAN_Signal;
    fb_tfuel            : FB_CAN_Signal;
    fb_toil             : FB_CAN_Signal;
    fb_prail_650        : FB_CAN_Signal;

    (* Kanal 2: Botschaft 16#660 *)
    fb_msv_divy_angle   : FB_CAN_Signal;
    fb_angle_eng_hdp    : FB_CAN_Signal;
    fb_tinj             : FB_CAN_Signal;
    fb_prail_660        : FB_CAN_Signal;

    (* Kanal 3: Botschaft 16#670 *)
    fb_tEKP             : FB_CAN_Signal;
    fb_pEKP             : FB_CAN_Signal;
    fb_pfuel            : FB_CAN_Signal;

    (* ======================================================================== *)
    (* 3. Signal-Instanzen zum SCHREIBEN auf Kanal 5 (ID 16#680)               *)
    (* ======================================================================== *)
    fb_Write_Mode       : FB_CAN_Signal; (* Bits 0..7  (8 Bit): Betriebsmodus *)
    fb_Write_Setpoint   : FB_CAN_Signal; (* Bits 8..23 (16 Bit): Sollwert *)
    fb_Write_Enable     : FB_CAN_Signal; (* Bit 24     (1 Bit): Freigabe *)
    fb_Write_Reset      : FB_CAN_Signal; (* Bit 25     (1 Bit): Reset *)
    fb_Write_Start      : FB_CAN_Signal; (* Bit 26     (1 Bit): Start *)

    (* ======================================================================== *)
    (* 4. Lokale Prozessvariablen für ALLE gelesenen Messwerte                  *)
    (* ======================================================================== *)
    rTecu_cpu           : REAL; (* ID 16#456: ECU CPU Temperatur *)
    rPrail_nom          : REAL; (* ID 16#650: Sollwert Raildruck *)
    rTfuel              : REAL; (* ID 16#650: Kraftstofftemperatur *)
    rToil               : REAL; (* ID 16#650: Öltemperatur *)
    rPrail_650          : REAL; (* ID 16#650: Istwert Raildruck *)
    rMsv_divy_angle     : REAL; (* ID 16#660: MSV Förderwinkel *)
    rAngle_eng_hdp      : REAL; (* ID 16#660: Motorwinkel HDP Messung *)
    rTinj               : REAL; (* ID 16#660: Einspritzdauer *)
    rPrail_660          : REAL; (* ID 16#660: Redundanzer Istwert Raildruck *)
    rTekp               : REAL; (* ID 16#670: Temperatur Kraftstoffpumpe EKP *)
    rPekp               : REAL; (* ID 16#670: Druck Kraftstoffpumpe EKP *)
    rPfuel              : REAL; (* ID 16#670: Kraftstoffdruck *)

    (* ======================================================================== *)
    (* 5. Lokale Variablen für die zu SCHREIBENDEN Werte (ID 16#680)            *)
    (* ======================================================================== *)
    nWrite_Mode         : USINT := 1;        (* Betriebsmodus (0..255) *)
    rWrite_Setpoint     : REAL  := 1500.0;   (* Physikalischer Sollwert (16 Bit) *)
    bWrite_Enable       : BOOL  := TRUE;     (* Bool 1: Freigabe *)
    bWrite_Reset        : BOOL  := FALSE;    (* Bool 2: Reset *)
    bWrite_Start        : BOOL  := TRUE;     (* Bool 3: Start *)

    (* Sende-Taktung über SPS-Zyklen (bei 10 ms Task: 10 Zyklen = exakt 100 ms) *)
    bContinuousSend     : BOOL := TRUE;      (* TRUE = Kontinuierlich jeden 10. Zyklus senden *)
    nCycleCounter       : INT  := 0;         (* Zykluszähler *)
    nTargetCycles       : INT  := 10;        (* 10 Zyklen à 10 ms = exakt 100.0 ms *)
    bSendTrigger680     : BOOL := FALSE;     (* Manueller Einzeltakt-Trigger *)
END_VAR

(* ============================================================================ *)
(* Initialisierung der Kanal-Maske                                              *)
(* ============================================================================ *)
IF NOT bConfigDone THEN
    canChannels[1].RxCobId := 16#650;  (* Kanal 1 (Rx): ID 0x650 *)
    canChannels[2].RxCobId := 16#660;  (* Kanal 2 (Rx): ID 0x660 *)
    canChannels[3].RxCobId := 16#670;  (* Kanal 3 (Rx): ID 0x670 *)
    canChannels[4].RxCobId := 16#456;  (* Kanal 4 (Rx): ID 0x456 (tecu_cpu) *)
    canChannels[5].TxCobId := 16#680;  (* Kanal 5 (Tx): ID 0x680 (Schreiben) *)
    bConfigDone := TRUE;
END_IF;

(* ============================================================================ *)
(* 1. Hardware CAN-Broker aufrufen (verarbeitet Kanäle 1..5)                    *)
(* ============================================================================ *)
fbBroker(
    Enable      := TRUE,
    Reset       := FALSE,
    NetNb       := 1,
    CardNb      := 2,
    Chan        := 0,
    NumChannels := 5,
    Channels    := canChannels,
    Ready       => bBrokerReady,
    Error       => bBrokerError,
    ErrorID     => nBrokerErrorID
);

(* ============================================================================ *)
(* 2. LESEN: Kanal 4 -> ID 16#456 (tecu_cpu)                                    *)
(* ============================================================================ *)
fb_tecu_cpu(
    CobId     := 16#456,
    StartBit  := 0,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[4].RxData
);
rTecu_cpu := fb_tecu_cpu.PhysValue;

(* ============================================================================ *)
(* 3. LESEN: Kanal 1 -> ID 16#650 (prail_nom, tfuel, toil, prail)               *)
(* ============================================================================ *)
fb_prail_nom(
    CobId     := 16#650,
    StartBit  := 0,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[1].RxData
);
rPrail_nom := fb_prail_nom.PhysValue;

fb_tfuel(
    CobId     := 16#650,
    StartBit  := 16,
    BitLength := 8,
    bWrite    := FALSE,
    Data      := canChannels[1].RxData
);
rTfuel := fb_tfuel.PhysValue;

fb_toil(
    CobId     := 16#650,
    StartBit  := 24,
    BitLength := 8,
    bWrite    := FALSE,
    Data      := canChannels[1].RxData
);
rToil := fb_toil.PhysValue;

fb_prail_650(
    CobId     := 16#650,
    StartBit  := 48,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[1].RxData
);
rPrail_650 := fb_prail_650.PhysValue;

(* ============================================================================ *)
(* 4. LESEN: Kanal 2 -> ID 16#660 (msv_divy_angle, angle_eng_hdp, tinj, prail)  *)
(* ============================================================================ *)
fb_msv_divy_angle(
    CobId     := 16#660,
    StartBit  := 0,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[2].RxData
);
rMsv_divy_angle := fb_msv_divy_angle.PhysValue;

fb_angle_eng_hdp(
    CobId     := 16#660,
    StartBit  := 16,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[2].RxData
);
rAngle_eng_hdp := fb_angle_eng_hdp.PhysValue;

fb_tinj(
    CobId     := 16#660,
    StartBit  := 32,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[2].RxData
);
rTinj := fb_tinj.PhysValue;

fb_prail_660(
    CobId     := 16#660,
    StartBit  := 48,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[2].RxData
);
rPrail_660 := fb_prail_660.PhysValue;

(* ============================================================================ *)
(* 5. LESEN: Kanal 3 -> ID 16#670 (tEKP, pEKP, pfuel)                           *)
(* ============================================================================ *)
fb_tEKP(
    CobId     := 16#670,
    StartBit  := 0,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[3].RxData
);
rTekp := fb_tEKP.PhysValue;

fb_pEKP(
    CobId     := 16#670,
    StartBit  := 16,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[3].RxData
);
rPekp := fb_pEKP.PhysValue;

fb_pfuel(
    CobId     := 16#670,
    StartBit  := 32,
    BitLength := 8,
    bWrite    := FALSE,
    Data      := canChannels[3].RxData
);
rPfuel := fb_pfuel.PhysValue;

(* ============================================================================ *)
(* 6. SCHREIBEN: Kanal 5 -> ID 16#680 alle 10 Zyklen (exakt 100 ms) senden     *)
(* ============================================================================ *)
IF bContinuousSend THEN
    nCycleCounter := nCycleCounter + 1;
END_IF;

(* Senden auslösen: Exakt bei jedem 10. SPS-Durchlauf ODER per manuellem Trigger *)
IF ((bContinuousSend AND (nCycleCounter >= nTargetCycles)) OR bSendTrigger680) 
   AND NOT canChannels[5].TxBusy THEN
    
    nCycleCounter := 0; (* Zähler zurücksetzen *)

    (* Signal 1: 8 Bit an Start-Bit 0 (Byte 0) *)
    fb_Write_Mode(
        CobId      := 16#680,
        StartBit   := 0,
        BitLength  := 8,
        bWrite     := TRUE,
        WriteValue := USINT_TO_REAL(nWrite_Mode),
        Data       := canChannels[5].TxData
    );

    (* Signal 2: 16 Bit an Start-Bit 8 (Byte 1 und 2) *)
    fb_Write_Setpoint(
        CobId      := 16#680,
        StartBit   := 8,
        BitLength  := 16,
        bWrite     := TRUE,
        WriteValue := rWrite_Setpoint,
        Data       := canChannels[5].TxData
    );

    (* Bool 1: Freigabe an Start-Bit 24 (Byte 3, Bit 0) *)
    fb_Write_Enable(
        CobId      := 16#680,
        StartBit   := 24,
        BitLength  := 1,
        bWrite     := TRUE,
        WriteValue := SEL(bWrite_Enable, 0.0, 1.0),
        Data       := canChannels[5].TxData
    );

    (* Bool 2: Reset an Start-Bit 25 (Byte 3, Bit 1) *)
    fb_Write_Reset(
        CobId      := 16#680,
        StartBit   := 25,
        BitLength  := 1,
        bWrite     := TRUE,
        WriteValue := SEL(bWrite_Reset, 0.0, 1.0),
        Data       := canChannels[5].TxData
    );

    (* Bool 3: Start an Start-Bit 26 (Byte 3, Bit 2) *)
    fb_Write_Start(
        CobId      := 16#680,
        StartBit   := 26,
        BitLength  := 1,
        bWrite     := TRUE,
        WriteValue := SEL(bWrite_Start, 0.0, 1.0),
        Data       := canChannels[5].TxData
    );

    (* ------------------------------------------------------------------------ *)
    (* Sendeanforderung EINMAL auslösen, nachdem alle Bits gepackt sind          *)
    (* ------------------------------------------------------------------------ *)
    canChannels[5].TxReq := TRUE;
    bSendTrigger680      := FALSE;

END_IF;

END_PROGRAM
