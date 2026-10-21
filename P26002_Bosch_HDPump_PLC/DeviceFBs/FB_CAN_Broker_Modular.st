(********************************************************************************
 * FUNCTION_BLOCK: FB_CAN_Broker_Modular
 * 
 * Beschreibung:
 *   Vollständig modularer Hardware-Treiber-Manager für den CAN-Bus an Bachmann M1.
 *   
 *   Vorteile:
 *     1. Dynamische Kanalanzahl: Über den Input 'NumChannels' wird festgelegt,
 *        wie viele Kanäle (1..16) aktiv genutzt werden.
 *     2. Vorgegebene Konfigurationstabelle ("Maske"):
 *        Alle CAN-IDs werden in einem Array 'Channels' übergeben.
 *     3. Automatische Schleifenabarbeitung:
 *        - Schaltet alle konfigurierten RxCobIds automatisch beim CAN-Controller frei.
 *        - Verteilt eintreffende Telegramme dynamisch auf den passenden Kanal.
 *        - Faires Round-Robin Sende-Management über alle aktiven Kanäle.
 *     4. Universelle Telegrammlänge (Msg_Length >= 1):
 *        Auch kurze Frames (1 Byte oder 2 Bytes) werden zuverlässig verarbeitet.
 ********************************************************************************)
FUNCTION_BLOCK FB_CAN_Broker_Modular
VAR_INPUT
    Enable          : BOOL := TRUE;             (* Broker aktivieren *)
    Reset           : BOOL := FALSE;            (* Re-Init auslösen *)
    NetNb           : DINT := 1;                (* CAN NetNumber (Standard: 1) *)
    CardNb          : DINT := 2;                (* CPU Card Number (Card 2) *)
    Chan            : UDINT := 0;               (* CAN-Kanal (0 = CAN A) *)
    NumChannels     : INT := 5;                 (* Anzahl der aktiv genutzten Kanäle (1..32) *)
END_VAR

VAR_IN_OUT
    (* Konfigurationstabelle / Maske aller Kanäle *)
    Channels        : ARRAY [1..32] OF ST_CAN_Broker_Channel;
END_VAR

VAR_OUTPUT
    Ready           : BOOL := FALSE;            (* Treiber initialisiert & betriebsbereit *)
    Error           : BOOL := FALSE;            (* Hardware- oder Konfigurationsfehler *)
    ErrorID         : DINT := 0;
    ActiveCount     : INT := 0;                 (* Tatsächlich überwachte Kanäle *)
END_VAR

VAR
    initStep        : INT := 0;
    initDone        : BOOL := FALSE;
    
    (* CUL Instanzen *)
    fbAttachEvent   : CUL_AttachEvent;
    fbSendMsg       : CUL_SendMsg_NB;
    fbRecvMsg       : CUL_ReceiveMsg;
    
    dwEventFlags    : UDINT := 0;
    nRet            : DINT := 0;
    
    (* Dynamische Rx-ID-Registrierung *)
    lastEnabledRx   : ARRAY [1..32] OF UDINT;
    
    (* Sende-Verwaltung *)
    txActive        : BOOL := FALSE;
    activeChan      : INT := 0;
    lastServedChan  : INT := 1;
    currTxCobId     : UDINT := 0;
    currTxData      : ARRAY [0..7] OF BYTE;
    
    (* Hilfsvariablen *)
    i               : INT;
    nActive         : INT;
    candChan        : INT;
    rxCount         : INT;
END_VAR

(* Begrenzung der aktiven Kanalanzahl auf 1..32 *)
nActive := NumChannels;
IF nActive < 1 THEN
    nActive := 1;
ELSIF nActive > 32 THEN
    nActive := 32;
END_IF;
ActiveCount := nActive;

(* ============================================================================ *)
(* Deaktivierung & Reset                                                       *)
(* ============================================================================ *)
IF NOT Enable THEN
    IF initDone THEN
        Cul_DetachEvent(NetNb := NetNb, Event := 0);
    END_IF;
    Ready    := FALSE;
    initDone := FALSE;
    initStep := 0;
    txActive := FALSE;
    RETURN;
END_IF;

IF Reset THEN
    IF initDone THEN
        Cul_DetachEvent(NetNb := NetNb, Event := 0);
    END_IF;
    Ready          := FALSE;
    Error          := FALSE;
    ErrorID        := 0;
    initDone       := FALSE;
    initStep       := 0;
    txActive       := FALSE;
    FOR i := 1 TO 32 DO
        lastEnabledRx[i] := 0;
    END_FOR;
END_IF;

(* ============================================================================ *)
(* Initialisierung der Hardware (Schritt 0)                                     *)
(* ============================================================================ *)
IF NOT initDone THEN
    CASE initStep OF
        0:
            (* Alle aktiven RxCobIds beim CAN-Controller freischalten *)
            FOR i := 1 TO nActive DO
                IF Channels[i].RxCobId > 0 AND Channels[i].RxCobId <> lastEnabledRx[i] THEN
                    nRet := Cul_EnableMsg(CardNb := CardNb, Chan := Chan, CobId := Channels[i].RxCobId);
                    lastEnabledRx[i] := Channels[i].RxCobId;
                END_IF;
            END_FOR;
            
            dwEventFlags := 0;
            fbAttachEvent(Req := TRUE, NetNb := NetNb, Event := dwEventFlags);
            
            IF fbAttachEvent.Done THEN
                fbAttachEvent(Req := FALSE, NetNb := NetNb, Event := dwEventFlags);
                initDone := TRUE;
                Ready    := TRUE;
                Error    := FALSE;
                ErrorID  := 0;
            ELSIF fbAttachEvent.Error THEN
                Error    := TRUE;
                ErrorID  := fbAttachEvent.Status;
            END_IF;
    END_CASE;
    RETURN;
END_IF;

(* Nachträglich veränderte RxCobIds dynamisch nachregistrieren *)
FOR i := 1 TO nActive DO
    IF Channels[i].RxCobId > 0 AND Channels[i].RxCobId <> lastEnabledRx[i] THEN
        nRet := Cul_EnableMsg(CardNb := CardNb, Chan := Chan, CobId := Channels[i].RxCobId);
        lastEnabledRx[i] := Channels[i].RxCobId;
    END_IF;
END_FOR;

(* ============================================================================ *)
(* Zyklus-Start: Flanken und Trigger der aktiven Kanäle zurücksetzen            *)
(* ============================================================================ *)
FOR i := 1 TO nActive DO
    Channels[i].RxNew   := FALSE;
    Channels[i].TxDone  := FALSE;
    Channels[i].TxError := FALSE;
END_FOR;

(* ============================================================================ *)
(* 1. EMPFANG: Hardware-Queue leeren & an Kanäle 1..nActive verteilen           *)
(* ============================================================================ *)
rxCount := 0;
REPEAT
    fbRecvMsg(NetNb := NetNb);
    rxCount := rxCount + 1;
    
    IF fbRecvMsg.Status = 0 AND fbRecvMsg.Msg_Length >= 1 THEN
        FOR i := 1 TO nActive DO
            IF Channels[i].RxCobId = fbRecvMsg.CobId THEN
                Channels[i].RxNew  := TRUE;
                Channels[i].RxData := fbRecvMsg.Msg_Data;
                Channels[i].RxLen  := fbRecvMsg.Msg_Length;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;
UNTIL (fbRecvMsg.Status <> 0) OR (fbRecvMsg.Msg_Left = 0) OR (rxCount > 30)
END_REPEAT;

(* ============================================================================ *)
(* 2. SENDEN: Laufende Übertragung überwachen oder neuen Auftrag starten        *)
(* ============================================================================ *)
IF txActive THEN
    fbSendMsg(
        Req        := TRUE,
        NetNb      := NetNb,
        CobId      := currTxCobId,
        Msg_Data   := currTxData,
        Msg_Length := 8
    );
    
    IF fbSendMsg.Done THEN
        fbSendMsg(Req := FALSE, NetNb := NetNb, CobId := currTxCobId, Msg_Data := currTxData, Msg_Length := 8);
        txActive := FALSE;
        IF activeChan >= 1 AND activeChan <= nActive THEN
            Channels[activeChan].TxDone := TRUE;
            Channels[activeChan].TxBusy := FALSE;
            Channels[activeChan].TxReq  := FALSE;
        END_IF;
    ELSIF fbSendMsg.Error THEN
        fbSendMsg(Req := FALSE, NetNb := NetNb, CobId := currTxCobId, Msg_Data := currTxData, Msg_Length := 8);
        txActive := FALSE;
        IF activeChan >= 1 AND activeChan <= nActive THEN
            Channels[activeChan].TxError := TRUE;
            Channels[activeChan].TxBusy  := FALSE;
            Channels[activeChan].TxReq   := FALSE;
        END_IF;
    END_IF;

ELSE
    (* Round-Robin über alle nActive Kanäle *)
    FOR i := 1 TO nActive DO
        candChan := ((lastServedChan - 1 + i) MOD nActive) + 1;
        
        IF Channels[candChan].TxReq THEN
            activeChan                := candChan;
            lastServedChan            := candChan;
            currTxCobId               := Channels[candChan].TxCobId;
            currTxData                := Channels[candChan].TxData;
            Channels[candChan].TxBusy := TRUE;
            txActive                  := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF txActive THEN
        fbSendMsg(
            Req        := TRUE,
            NetNb      := NetNb,
            CobId      := currTxCobId,
            Msg_Data   := currTxData,
            Msg_Length := 8
        );
    END_IF;
END_IF;

END_FUNCTION_BLOCK
