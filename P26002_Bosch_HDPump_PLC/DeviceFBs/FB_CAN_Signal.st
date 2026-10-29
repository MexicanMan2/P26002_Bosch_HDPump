(********************************************************************************
 * FUNCTION_BLOCK: FB_CAN_Signal
 * 
 * Beschreibung:
 *   Universeller Signal-Baustein zur Extraktion (Lesen / Decodieren) und 
 *   Einbettung (Schreiben / Encodieren) von CAN-Signalen in das 8-Byte 
 *   Nutzdatenfeld (Data) einer CAN-Nachricht.
 *   
 *   Kompatibel mit Bachmann M-PLC (SolutionCenter):
 *     - Verwendet standardkonforme IEC 61131-3 Typkonvertierungen (<SOURCE>_TO_<TARGET>)
 *       (keine Kurzschreibweisen wie TO_UDINT, TO_DINT etc.).
 *     - Bit-Operationen (SHL, SHR, AND, OR, NOT) auf DWORD.
 *     - Entwickelt für Little-Endian (Intel-Format, Bosch Motorsport / RaceCon).
 ********************************************************************************)
FUNCTION_BLOCK FB_CAN_Signal
VAR_INPUT
    CobId       : UDINT := 0;       (* CAN Identifier (z. B. 16#650) zur Zuordnung/Doku *)
    StartBit    : UINT  := 0;       (* Start-Bit im CAN-Frame (0..63, LSB bei Little Endian) *)
    BitLength   : UINT  := 16;      (* Länge des Signals in Bits (1..32) *)
    IsSigned    : BOOL  := FALSE;   (* FALSE: Unsigned, TRUE: Signed *)
    Factor      : REAL  := 1.0;     (* Skalierungsfaktor: PhysValue = Raw * Factor + Offset *)
    Offset      : REAL  := 0.0;     (* Skalierungs-Offset *)
    bWrite      : BOOL  := FALSE;   (* FALSE = Lesen (Decode), TRUE = Schreiben (Encode) *)
    WriteValue  : REAL  := 0.0;     (* Zu schreibender physikalischer Wert (nur bei bWrite=TRUE) *)
END_VAR

VAR_IN_OUT
    Data        : ARRAY [0..7] OF BYTE; (* 8-Byte Nutzdatenfeld der CAN-Botschaft *)
END_VAR

VAR_OUTPUT
    RawValue    : UDINT := 0;       (* Extrahierter Rohwert als UDINT *)
    PhysValue   : REAL  := 0.0;     (* Skalierter physikalischer Messwert *)
    Valid       : BOOL  := FALSE;   (* Signal-Konfiguration gültig & Operation erfolgreich *)
    Error       : BOOL  := FALSE;   (* TRUE bei ungültigen Parametern (z.B. StartBit+Länge > 64) *)
END_VAR

VAR
    startByte   : UINT;
    bitOffset   : UINT;
    mask        : DWORD;
    signBit     : DWORD;
    dwRaw       : DWORD;
    dwRawWrite  : DWORD;
    nSignedVal  : DINT;
    rRawCalc    : REAL;
    i           : UINT;
    b           : UINT;
    currBitPos  : UINT;
    targetByte  : UINT;
    targetBit   : UINT;
    bitVal      : BOOL;
END_VAR

(* ============================================================================ *)
(* 1. Plausibilitätsprüfung der Signal-Parameter                                *)
(* ============================================================================ *)
IF (BitLength = 0) OR (BitLength > 32) OR ((StartBit + BitLength) > 64) THEN
    Error := TRUE;
    Valid := FALSE;
    RETURN;
END_IF;

Error := FALSE;
Valid := TRUE;

startByte := StartBit / 8;
bitOffset := StartBit MOD 8;

(* 32-Bit Bitmaske berechnen *)
IF BitLength >= 32 THEN
    mask := 16#FFFFFFFF;
ELSE
    mask := SHR(DWORD#16#FFFFFFFF, 32 - BitLength);
END_IF;

(* ============================================================================ *)
(* 2. SCHREIBEN (ENCODE): Signal in Data-Array einbetten                         *)
(* ============================================================================ *)
IF bWrite THEN
    IF Factor <> 0.0 THEN
        rRawCalc := (WriteValue - Offset) / Factor;
    ELSE
        rRawCalc := WriteValue;
    END_IF;

    nSignedVal := REAL_TO_DINT(rRawCalc);
    dwRawWrite := DINT_TO_DWORD(nSignedVal) AND mask;

    RawValue  := DWORD_TO_UDINT(dwRawWrite);
    PhysValue := WriteValue;

    (* Schnellpfad für byte-ausgerichtete Signale *)
    IF (bitOffset = 0) AND (BitLength = 8) THEN
        Data[startByte] := DWORD_TO_BYTE(dwRawWrite AND 16#FF);

    ELSIF (bitOffset = 0) AND (BitLength = 16) THEN
        Data[startByte]     := DWORD_TO_BYTE(dwRawWrite AND 16#FF);
        Data[startByte + 1] := DWORD_TO_BYTE(SHR(dwRawWrite, 8) AND 16#FF);

    ELSIF (bitOffset = 0) AND (BitLength = 24) THEN
        Data[startByte]     := DWORD_TO_BYTE(dwRawWrite AND 16#FF);
        Data[startByte + 1] := DWORD_TO_BYTE(SHR(dwRawWrite, 8) AND 16#FF);
        Data[startByte + 2] := DWORD_TO_BYTE(SHR(dwRawWrite, 16) AND 16#FF);

    ELSIF (bitOffset = 0) AND (BitLength = 32) THEN
        Data[startByte]     := DWORD_TO_BYTE(dwRawWrite AND 16#FF);
        Data[startByte + 1] := DWORD_TO_BYTE(SHR(dwRawWrite, 8) AND 16#FF);
        Data[startByte + 2] := DWORD_TO_BYTE(SHR(dwRawWrite, 16) AND 16#FF);
        Data[startByte + 3] := DWORD_TO_BYTE(SHR(dwRawWrite, 24) AND 16#FF);

    ELSE
        (* Universeller Pfad: Bitgenaues Read-Modify-Write *)
        FOR b := 0 TO (BitLength - 1) DO
            currBitPos := StartBit + b;
            targetByte := currBitPos / 8;
            targetBit  := currBitPos MOD 8;
            bitVal     := (SHR(dwRawWrite, b) AND 16#1) <> 16#0;

            IF targetByte <= 7 THEN
                IF bitVal THEN
                    Data[targetByte] := Data[targetByte] OR DWORD_TO_BYTE(SHL(DWORD#16#1, targetBit));
                ELSE
                    Data[targetByte] := Data[targetByte] AND NOT DWORD_TO_BYTE(SHL(DWORD#16#1, targetBit));
                END_IF;
            END_IF;
        END_FOR;
    END_IF;

    RETURN;
END_IF;

(* ============================================================================ *)
(* 3. LESEN (DECODE): Signal aus Data-Array extrahieren (Little Endian)        *)
(* ============================================================================ *)
(* Schnellpfad für byte-ausgerichtete Signale *)
IF (bitOffset = 0) AND (BitLength = 8) THEN
    dwRaw := BYTE_TO_DWORD(Data[startByte]);

ELSIF (bitOffset = 0) AND (BitLength = 16) THEN
    dwRaw := BYTE_TO_DWORD(Data[startByte]) OR SHL(BYTE_TO_DWORD(Data[startByte + 1]), 8);

ELSIF (bitOffset = 0) AND (BitLength = 24) THEN
    dwRaw := BYTE_TO_DWORD(Data[startByte]) 
          OR SHL(BYTE_TO_DWORD(Data[startByte + 1]), 8) 
          OR SHL(BYTE_TO_DWORD(Data[startByte + 2]), 16);

ELSIF (bitOffset = 0) AND (BitLength = 32) THEN
    dwRaw := BYTE_TO_DWORD(Data[startByte]) 
          OR SHL(BYTE_TO_DWORD(Data[startByte + 1]), 8) 
          OR SHL(BYTE_TO_DWORD(Data[startByte + 2]), 16) 
          OR SHL(BYTE_TO_DWORD(Data[startByte + 3]), 24);

ELSE
    (* Universeller Pfad: Bis zu 5 Bytes zusammenführen und shiften *)
    dwRaw := 16#0;
    FOR i := 0 TO 3 DO
        IF (startByte + i) <= 7 THEN
            dwRaw := dwRaw OR SHL(BYTE_TO_DWORD(Data[startByte + i]), i * 8);
        END_IF;
    END_FOR;

    IF bitOffset > 0 THEN
        dwRaw := SHR(dwRaw, bitOffset);
        IF (startByte + 4) <= 7 THEN
            dwRaw := dwRaw OR SHL(BYTE_TO_DWORD(Data[startByte + 4]), 32 - bitOffset);
        END_IF;
    END_IF;

    dwRaw := dwRaw AND mask;
END_IF;

RawValue := DWORD_TO_UDINT(dwRaw);

(* ============================================================================ *)
(* 4. Vorzeichen-Erweiterung (Sign Extension) und Skalierung                    *)
(* ============================================================================ *)
IF IsSigned THEN
    signBit := SHL(DWORD#16#1, BitLength - 1);
    IF (dwRaw AND signBit) <> 16#0 THEN
        (* Negative Zahl: Führende Einsen auffüllen *)
        dwRaw := dwRaw OR (NOT mask);
    END_IF;
    nSignedVal := DWORD_TO_DINT(dwRaw);
    PhysValue  := (DINT_TO_REAL(nSignedVal) * Factor) + Offset;
ELSE
    nSignedVal := DWORD_TO_DINT(dwRaw);
    PhysValue  := (DINT_TO_REAL(nSignedVal) * Factor) + Offset;
END_IF;

END_FUNCTION_BLOCK
