(********************************************************************************
 * PROGRAM: PRG_MS7_CAN_Handler
 * 
 * Beschreibung:
 *   Erweitertes Anwendungsbeispiel für das Auslesen und Schreiben des 
 *   CAN-Netzwerks (Bosch MS7 Logger / ECU) an einer Bachmann M1 Steuerung.
 * 
 *   KANAL-ÜBERSICHT:
 *   ----------------------------------------------------------------------------
 *   EMPFANG (R / Rx):
 *     - Kanal 1 (Rx): ID 16#650 (prail_nom, tfuel, toil, prail_650)
 *     - Kanal 2 (Rx): ID 16#660 (msv_divy_angle, angle_eng_hdp, tinj, prail_660)
 *     - Kanal 3 (Rx): ID 16#670 (tEKP, pEKP, pfuel)
 *     - Kanal 4 (Rx): ID 16#456 (tecu_cpu)
 *     - Kanal 5 (Rx): ID 16#680 (Drehzahl / RPM)
 * 
 *   SENDEN (W / Tx):
 *     - Kanal 6  (Tx): ID 16#700 (Set RPM, Actual RPM, valid RPM)
 *     - Kanal 7  (Tx): ID 16#710 (Oil pressure, Oil temperature, Status OK-Bits)
 *     - Kanal 8  (Tx): ID 16#720 (Fuel temp, Fuel supply press, Status OK-Bits)
 *     - Kanal 9  (Tx): ID 16#730 (Fuel Mass Flow 1, 2, 3, valid Bit)
 *     - Kanal 10 (Tx): ID 16#800 (ERROR_Bits)
 *     - Kanal 11 (Tx): ID 16#900 (Counter LAP, Counter FREE TRIGGER)
 *     - Kanal 12 (Tx): ID 16#910 (RPM Profile - reserviert)
 ********************************************************************************)
PROGRAM PRG_MS7_CAN_Handler
VAR
    (* ======================================================================== *)
    (* 1. Konfigurationstabelle / Maske aller CAN-Kanäle (Botschaftsebene)      *)
    (* ======================================================================== *)
    canChannels                 : ARRAY [1..32] OF ST_CAN_Broker_Channel;
    bConfigDone                 : BOOL := FALSE;

    (* Hardware CAN-Broker Instanz (modular bis 32 Kanäle) *)
    fbBroker                    : FB_CAN_Broker_Modular;
    bBrokerReady                : BOOL;
    bBrokerError                : BOOL;
    nBrokerErrorID              : DINT;

    (* ======================================================================== *)
    (* 2. Signal-Instanzen zum LESEN (Rx)                                       *)
    (* ======================================================================== *)
    (* Kanal 4: Botschaft 16#456 (1110 dez) *)
    fb_tecu_cpu                 : FB_CAN_Signal;

    (* Kanal 1: Botschaft 16#650 (1616 dez) *)
    fb_prail_nom                : FB_CAN_Signal; (* Fuel press HP - set point (Bit 0, 16 Bit) *)
    fb_tfuel                    : FB_CAN_Signal; (* Fuel temp HP (Bit 16, 8 Bit) *)
    fb_toil                     : FB_CAN_Signal; (* Oil temp (Bit 24, 8 Bit) *)
    fb_prail_650                : FB_CAN_Signal; (* Fuel press HP - side 1 (Bit 48, 16 Bit) *)

    (* Kanal 2: Botschaft 16#660 (1632 dez) *)
    fb_msv_divy_angle           : FB_CAN_Signal;
    fb_angle_eng_hdp            : FB_CAN_Signal;
    fb_tinj                     : FB_CAN_Signal;
    fb_prail_660                : FB_CAN_Signal; (* Fuel press HP - side 2 (Bit 48, 16 Bit) *)

    (* Kanal 3: Botschaft 16#670 (1648 dez) *)
    fb_tEKP                     : FB_CAN_Signal; (* Fuel temp after low press pump (Bit 0, 16 Bit) *)
    fb_pEKP                     : FB_CAN_Signal; (* Fuel press after low press pump (Bit 16, 16 Bit) *)
    fb_pfuel                    : FB_CAN_Signal; (* Fuel pressure (Bit 32, 8 Bit) *)

    (* Kanal 5: Botschaft 16#680 (1664 dez) *)
    fb_engine_RPM               : FB_CAN_Signal; (* Drehzahl / RPM (Bit 0, 16 Bit) *)

    (* ======================================================================== *)
    (* 3. Signal-Instanzen zum SCHREIBEN (Tx)                                   *)
    (* ======================================================================== *)
    (* Kanal 6: Botschaft 16#700 (1792 dez) *)
    fb_w_Set_RPM                : FB_CAN_Signal; (* Set RPM (Bit 0, 16 Bit) *)
    fb_w_Actual_RPM             : FB_CAN_Signal; (* Actual RPM (Bit 16, 16 Bit) *)
    fb_w_valid_RPM              : FB_CAN_Signal; (* valid RPM (Bit 32, 16 Bit) *)

    (* Kanal 7: Botschaft 16#710 (1808 dez) *)
    fb_w_Oil_pressure           : FB_CAN_Signal; (* Oil pressure (Bit 0, 16 Bit) *)
    fb_w_Oil_temperature        : FB_CAN_Signal; (* Oil temperature (Bit 16, 16 Bit) *)
    fb_w_Oil_pressure_OK        : FB_CAN_Signal; (* Oil pressure OK (Bit 32, 1 Bit) *)
    fb_w_Oil_temperature_OK     : FB_CAN_Signal; (* Oil temperature OK (Bit 33, 1 Bit) *)

    (* Kanal 8: Botschaft 16#720 (1824 dez) *)
    fb_w_Fuel_temperature       : FB_CAN_Signal; (* Fuel temperature (Bit 0, 16 Bit) *)
    fb_w_Fuel_supply_pressure   : FB_CAN_Signal; (* Fuel supply pressure (Bit 16, 16 Bit) *)
    fb_w_Fuel_temperature_OK    : FB_CAN_Signal; (* Fuel temperature OK (Bit 32, 1 Bit) *)
    fb_w_Fuel_supply_press_OK   : FB_CAN_Signal; (* Fuel supply pressure OK (Bit 33, 1 Bit) *)

    (* Kanal 9: Botschaft 16#730 (1840 dez) *)
    fb_w_Fuel_Mass_Flow_1       : FB_CAN_Signal; (* Fuel Mass Flow 1 (Bit 0, 16 Bit) *)
    fb_w_Fuel_Mass_Flow_2       : FB_CAN_Signal; (* Fuel Mass Flow 2 (Bit 16, 16 Bit) *)
    fb_w_Fuel_Mass_Flow_3       : FB_CAN_Signal; (* Fuel Mass Flow 3 (Bit 32, 16 Bit) *)
    fb_w_valid_Fuel_Mass_Flow   : FB_CAN_Signal; (* valid Fuel Mass Flow (Bit 48, 1 Bit) *)

    (* Kanal 10: Botschaft 16#800 (2048 dez) *)
    fb_w_ERROR_Bits             : FB_CAN_Signal; (* ERROR_Bits (Bit 0, 16 Bit) *)

    (* Kanal 11: Botschaft 16#900 (2304 dez) *)
    fb_w_Counter_LAP            : FB_CAN_Signal; (* Counter Byte 1 (LAP) (Bit 0, 8 Bit) *)
    fb_w_Counter_FREE_TRIGGER   : FB_CAN_Signal; (* Counter Byte 2 (FREE TRIGGER) (Bit 8, 8 Bit) *)

    (* Kanal 12: Botschaft 16#910 (2320 dez) *)
    fb_w_RPM_Profile            : FB_CAN_Signal; (* RPM Profile (reserviert) *)

(*     (* ======================================================================== *) *)
(*     (* 4. Lokale Prozessvariablen für ALLE gelesenen Messwerte (Rx)             *) *)
(*     (* ======================================================================== *) *)
(*     rTecu_cpu                   : REAL; (* ID 16#456: ECU CPU Temperatur *) *)
(*     rPrail_nom                  : REAL; (* ID 16#650: Fuel pressure HP - set point *) *)
(*     rTfuel                      : REAL; (* ID 16#650: Fuel temperature HP *) *)
(*     rToil                       : REAL; (* ID 16#650: Öltemperatur *) *)
(*     rPrail_650                  : REAL; (* ID 16#650: Fuel pressure HP - side 1 *) *)
(*     rMsv_divy_angle             : REAL; (* ID 16#660: MSV Förderwinkel *) *)
(*     rAngle_eng_hdp              : REAL; (* ID 16#660: Motorwinkel HDP Messung *) *)
(*     rTinj                       : REAL; (* ID 16#660: Einspritzdauer *) *)
(*     rPrail_660                  : REAL; (* ID 16#660: Fuel pressure HP - side 2 *) *)
(*     rTekp                       : REAL; (* ID 16#670: Fuel temp after low press pump *) *)
(*     rPekp                       : REAL; (* ID 16#670: Fuel press after low press pump *) *)
(*     rPfuel                      : REAL; (* ID 16#670: Kraftstoffdruck *) *)
(*     rEngine_RPM                 : REAL; (* ID 16#680: Drehzahl / RPM *) *)
(*  *)
(*     (* ======================================================================== *) *)
(*     (* 5. Lokale Variablen für die zu SCHREIBENDEN Werte (Tx)                   *) *)
(*     (* ======================================================================== *) *)
(*     (* ID 16#700 *) *)
(*     rWrite_Set_RPM              : REAL  := 2500.0; *)
(*     rWrite_Actual_RPM           : REAL  := 2498.0; *)
(*     bWrite_valid_RPM            : BOOL  := TRUE; *)
(*  *)
(*     (* ID 16#710 *) *)
(*     rWrite_Oil_pressure         : REAL  := 4.5;    (* bar *) *)
(*     rWrite_Oil_temperature      : REAL  := 85.0;   (* °C *) *)
(*     bWrite_Oil_pressure_OK      : BOOL  := TRUE; *)
(*     bWrite_Oil_temperature_OK   : BOOL  := TRUE; *)
(*  *)
(*     (* ID 16#720 *) *)
(*     rWrite_Fuel_temperature     : REAL  := 25.0;   (* °C *) *)
(*     rWrite_Fuel_supply_pressure : REAL  := 5.0;    (* bar *) *)
(*     bWrite_Fuel_temperature_OK  : BOOL  := TRUE; *)
(*     bWrite_Fuel_supply_press_OK : BOOL  := TRUE; *)
(*  *)
(*     (* ID 16#730 *) *)
(*     rWrite_Fuel_Mass_Flow_1     : REAL  := 12.5;   (* kg/h *) *)
(*     rWrite_Fuel_Mass_Flow_2     : REAL  := 12.4; *)
(*     rWrite_Fuel_Mass_Flow_3     : REAL  := 0.0; *)
(*     bWrite_valid_Fuel_Mass_Flow : BOOL  := TRUE; *)
(*  *)
(*     (* ID 16#800 *) *)
(*     wWrite_ERROR_Bits           : WORD  := 16#0000; *)
(*  *)
(*     (* ID 16#900 *) *)
(*     nWrite_Counter_LAP          : USINT := 1; *)
(*     nWrite_Counter_FREE_TRIGGER : USINT := 0; *)
(*  *)
(*     (* ID 16#910 (reserviert) *) *)
(*     wWrite_RPM_Profile          : WORD  := 16#0000; *)

    (* ======================================================================== *)
    (* 6. Sende-Steuerung (Zykluszähler für 10 ms Task -> 100 ms Takt)         *)
    (* ======================================================================== *)
    bContinuousSend             : BOOL := TRUE;      (* TRUE = Kontinuierlich alle 100 ms senden *)
    nCycleCounter               : INT  := 0;         (* Zykluszähler *)
    nTargetCycles               : INT  := 10;        (* 10 Zyklen à 10 ms = exakt 100.0 ms *)
    bSendTriggerManual          : BOOL := FALSE;     (* Manueller Einzeltakt-Trigger *)

    (* Einzelne Sende-Freigaben für jede Botschaft *)
    bEnableTx_700               : BOOL := TRUE;
    bEnableTx_710               : BOOL := TRUE;
    bEnableTx_720               : BOOL := TRUE;
    bEnableTx_730               : BOOL := TRUE;
    bEnableTx_800               : BOOL := TRUE;
    bEnableTx_900               : BOOL := TRUE;
    bEnableTx_910               : BOOL := FALSE;     (* Reserviert - Standard inaktiv *)
END_VAR

(* ============================================================================ *)
(* Initialisierung der Kanal-Maske (1..12)                                      *)
(* ============================================================================ *)
IF NOT bConfigDone THEN
    (* Empfangskanäle (Rx) *)
    canChannels[1].RxCobId := 16#650;  canChannels[1].TxCobId := 0;
    canChannels[2].RxCobId := 16#660;  canChannels[2].TxCobId := 0;
    canChannels[3].RxCobId := 16#670;  canChannels[3].TxCobId := 0;
    canChannels[4].RxCobId := 16#456;  canChannels[4].TxCobId := 0;
    canChannels[5].RxCobId := 16#680;  canChannels[5].TxCobId := 0;

    (* Sendekanäle (Tx) *)
    canChannels[6].TxCobId  := 16#700; canChannels[6].RxCobId  := 0;
    canChannels[7].TxCobId  := 16#710; canChannels[7].RxCobId  := 0;
    canChannels[8].TxCobId  := 16#720; canChannels[8].RxCobId  := 0;
    canChannels[9].TxCobId  := 16#730; canChannels[9].RxCobId  := 0;
    canChannels[10].TxCobId := 16#800; canChannels[10].RxCobId := 0;
    canChannels[11].TxCobId := 16#900; canChannels[11].RxCobId := 0;
    canChannels[12].TxCobId := 16#910; canChannels[12].RxCobId := 0;

    bConfigDone := TRUE;
END_IF;

(* ============================================================================ *)
(* 1. Hardware CAN-Broker aufrufen (NumChannels := 12)                          *)
(* ============================================================================ *)
fbBroker(
    Enable      := TRUE,
    Reset       := FALSE,
    NetNb       := 1,
    CardNb      := 2,
    Chan        := 0,
    NumChannels := 12,
    Channels    := canChannels,
    Ready       => bBrokerReady,
    Error       => bBrokerError,
    ErrorID     => nBrokerErrorID
);

(* ============================================================================ *)
(* 2. EMPFANGEN (Rx): Signale decodieren                                        *)
(* ============================================================================ *)

(* Kanal 4: ID 16#456 (tecu_cpu) *)
fb_tecu_cpu(
    CobId     := 16#456,
    StartBit  := 0,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[4].RxData
);
rTecu_cpu := fb_tecu_cpu.PhysValue;

(* Kanal 1: ID 16#650 *)
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

(* Kanal 2: ID 16#660 *)
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

(* Kanal 3: ID 16#670 *)
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

(* Kanal 5: ID 16#680 (Drehzahl / RPM) *)
fb_engine_RPM(
    CobId     := 16#680,
    StartBit  := 0,
    BitLength := 16,
    bWrite    := FALSE,
    Data      := canChannels[5].RxData
);
rEngine_RPM := fb_engine_RPM.PhysValue;

(* ============================================================================ *)
(* 3. SENDEN (Tx): Botschaften packen und alle 100 ms an Broker übergeben       *)
(* ============================================================================ *)
IF bContinuousSend THEN
    nCycleCounter := nCycleCounter + 1;
END_IF;

(* Senden auslösen: Exakt bei jedem 10. SPS-Durchlauf (100 ms) oder per Trigger *)
IF ((bContinuousSend AND (nCycleCounter >= nTargetCycles)) OR bSendTriggerManual) THEN
    
    nCycleCounter := 0; (* Zähler zurücksetzen *)

    (* ------------------------------------------------------------------------ *)
    (* Kanal 6: ID 16#700 (Set RPM, Actual RPM, valid RPM)                      *)
    (* ------------------------------------------------------------------------ *)
    IF bEnableTx_700 AND NOT canChannels[6].TxBusy THEN
        fb_w_Set_RPM(
            CobId      := 16#700,
            StartBit   := 0,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Set_RPM,
            Data       := canChannels[6].TxData
        );
        fb_w_Actual_RPM(
            CobId      := 16#700,
            StartBit   := 16,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Actual_RPM,
            Data       := canChannels[6].TxData
        );
        fb_w_valid_RPM(
            CobId      := 16#700,
            StartBit   := 32,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := SEL(bWrite_valid_RPM, 0.0, 1.0),
            Data       := canChannels[6].TxData
        );
        canChannels[6].TxReq := TRUE;
    END_IF;

    (* ------------------------------------------------------------------------ *)
    (* Kanal 7: ID 16#710 (Oil pressure, Oil temperature, Status OK-Bits)       *)
    (* ------------------------------------------------------------------------ *)
    IF bEnableTx_710 AND NOT canChannels[7].TxBusy THEN
        fb_w_Oil_pressure(
            CobId      := 16#710,
            StartBit   := 0,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Oil_pressure,
            Data       := canChannels[7].TxData
        );
        fb_w_Oil_temperature(
            CobId      := 16#710,
            StartBit   := 16,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Oil_temperature,
            Data       := canChannels[7].TxData
        );
        fb_w_Oil_pressure_OK(
            CobId      := 16#710,
            StartBit   := 32,
            BitLength  := 1,
            bWrite     := TRUE,
            WriteValue := SEL(bWrite_Oil_pressure_OK, 0.0, 1.0),
            Data       := canChannels[7].TxData
        );
        fb_w_Oil_temperature_OK(
            CobId      := 16#710,
            StartBit   := 33,
            BitLength  := 1,
            bWrite     := TRUE,
            WriteValue := SEL(bWrite_Oil_temperature_OK, 0.0, 1.0),
            Data       := canChannels[7].TxData
        );
        canChannels[7].TxReq := TRUE;
    END_IF;

    (* ------------------------------------------------------------------------ *)
    (* Kanal 8: ID 16#720 (Fuel temp, Fuel supply press, Status OK-Bits)        *)
    (* ------------------------------------------------------------------------ *)
    IF bEnableTx_720 AND NOT canChannels[8].TxBusy THEN
        fb_w_Fuel_temperature(
            CobId      := 16#720,
            StartBit   := 0,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Fuel_temperature,
            Data       := canChannels[8].TxData
        );
        fb_w_Fuel_supply_pressure(
            CobId      := 16#720,
            StartBit   := 16,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Fuel_supply_pressure,
            Data       := canChannels[8].TxData
        );
        fb_w_Fuel_temperature_OK(
            CobId      := 16#720,
            StartBit   := 32,
            BitLength  := 1,
            bWrite     := TRUE,
            WriteValue := SEL(bWrite_Fuel_temperature_OK, 0.0, 1.0),
            Data       := canChannels[8].TxData
        );
        fb_w_Fuel_supply_press_OK(
            CobId      := 16#720,
            StartBit   := 33,
            BitLength  := 1,
            bWrite     := TRUE,
            WriteValue := SEL(bWrite_Fuel_supply_press_OK, 0.0, 1.0),
            Data       := canChannels[8].TxData
        );
        canChannels[8].TxReq := TRUE;
    END_IF;

    (* ------------------------------------------------------------------------ *)
    (* Kanal 9: ID 16#730 (Fuel Mass Flow 1, 2, 3, valid Bit)                   *)
    (* ------------------------------------------------------------------------ *)
    IF bEnableTx_730 AND NOT canChannels[9].TxBusy THEN
        fb_w_Fuel_Mass_Flow_1(
            CobId      := 16#730,
            StartBit   := 0,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Fuel_Mass_Flow_1,
            Data       := canChannels[9].TxData
        );
        fb_w_Fuel_Mass_Flow_2(
            CobId      := 16#730,
            StartBit   := 16,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Fuel_Mass_Flow_2,
            Data       := canChannels[9].TxData
        );
        fb_w_Fuel_Mass_Flow_3(
            CobId      := 16#730,
            StartBit   := 32,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := rWrite_Fuel_Mass_Flow_3,
            Data       := canChannels[9].TxData
        );
        fb_w_valid_Fuel_Mass_Flow(
            CobId      := 16#730,
            StartBit   := 48,
            BitLength  := 1,
            bWrite     := TRUE,
            WriteValue := SEL(bWrite_valid_Fuel_Mass_Flow, 0.0, 1.0),
            Data       := canChannels[9].TxData
        );
        canChannels[9].TxReq := TRUE;
    END_IF;

    (* ------------------------------------------------------------------------ *)
    (* Kanal 10: ID 16#800 (ERROR_Bits)                                         *)
    (* ------------------------------------------------------------------------ *)
    IF bEnableTx_800 AND NOT canChannels[10].TxBusy THEN
        fb_w_ERROR_Bits(
            CobId      := 16#800,
            StartBit   := 0,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := DINT_TO_REAL(WORD_TO_DINT(wWrite_ERROR_Bits)),
            Data       := canChannels[10].TxData
        );
        canChannels[10].TxReq := TRUE;
    END_IF;

    (* ------------------------------------------------------------------------ *)
    (* Kanal 11: ID 16#900 (Counter LAP, Counter FREE TRIGGER)                  *)
    (* ------------------------------------------------------------------------ *)
    IF bEnableTx_900 AND NOT canChannels[11].TxBusy THEN
        fb_w_Counter_LAP(
            CobId      := 16#900,
            StartBit   := 0,
            BitLength  := 8,
            bWrite     := TRUE,
            WriteValue := USINT_TO_REAL(nWrite_Counter_LAP),
            Data       := canChannels[11].TxData
        );
        fb_w_Counter_FREE_TRIGGER(
            CobId      := 16#900,
            StartBit   := 8,
            BitLength  := 8,
            bWrite     := TRUE,
            WriteValue := USINT_TO_REAL(nWrite_Counter_FREE_TRIGGER),
            Data       := canChannels[11].TxData
        );
        canChannels[11].TxReq := TRUE;
    END_IF;

    (* ------------------------------------------------------------------------ *)
    (* Kanal 12: ID 16#910 (RPM Profile - reserviert)                           *)
    (* ------------------------------------------------------------------------ *)
    IF bEnableTx_910 AND NOT canChannels[12].TxBusy THEN
        fb_w_RPM_Profile(
            CobId      := 16#910,
            StartBit   := 0,
            BitLength  := 16,
            bWrite     := TRUE,
            WriteValue := DINT_TO_REAL(WORD_TO_DINT(wWrite_RPM_Profile)),
            Data       := canChannels[12].TxData
        );
        canChannels[12].TxReq := TRUE;
    END_IF;

    bSendTriggerManual := FALSE;

END_IF;

END_PROGRAM
