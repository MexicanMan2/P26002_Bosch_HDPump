(********************************************************************************
 * FUNCTION_BLOCK: FB_MASS6000_DP
 * 
 * Beschreibung:
 *   Decodierung und Aufbereitung der PROFIBUS-DP / PROFINET Prozessdaten 
 *   des Coriolis-Massendurchflussmessers Siemens SITRANS FC MASSFLO MASS 6000
 *   über das ADFweb PROFINET/PROFIBUS Gateway HD67604-A1.
 * 
 *   Konfiguration: "Fall A" (4 Messwertmodule à 5 Byte = 20 Byte E/A)
 *   ----------------------------------------------------------------------------
 *   Offset (Bytes) | Messgröße          | Datentyp               | Umrechnung
 *   ----------------------------------------------------------------------------
 *   Byte 0..3      | Massflow (Masse)   | IEEE-754 Float (Big-E) | kg/s * 3600 -> kg/h
 *   Byte 4         | Status Massflow    | PA-Statusbyte (8 Bit)  | >= 16#80 = Good
 *   Byte 5..8      | Volumeflow (Vol.)  | IEEE-754 Float (Big-E) | m3/h bzw. l/h
 *   Byte 9         | Status Volumeflow  | PA-Statusbyte (8 Bit)  | >= 16#80 = Good
 *   Byte 10..13    | Density (Dichte)   | IEEE-754 Float (Big-E) | kg/l (1:1)
 *   Byte 14        | Status Density     | PA-Statusbyte (8 Bit)  | >= 16#80 = Good
 *   Byte 15..18    | Temperature (Temp) | IEEE-754 Float (Big-E) | Kelvin - 273.15 -> °C
 *   Byte 19        | Status Temperature | PA-Statusbyte (8 Bit)  | >= 16#80 = Good
 * 
 *   Kompatibel mit Bachmann M-PLC (SolutionCenter):
 *     - Standardkonforme Konvertierungen (<SOURCE>_TO_<TARGET>).
 *     - Bit-rekonstruierte Float-Wandlung über ADR() und POINTER TO REAL.
 ********************************************************************************)
FUNCTION_BLOCK FB_MASS6000_DP
VAR_INPUT
    bEnable             : BOOL := TRUE;             (* Baustein-Aktivierung *)
    Data                : ARRAY [0..19] OF BYTE;    (* 20-Byte PROFINET Eingangsbereich *)
END_VAR

VAR_OUTPUT
    rMassflow_kgh       : REAL := 0.0;              (* Massendurchfluss [kg/h] *)
    rVolumeflow         : REAL := 0.0;              (* Volumendurchfluss [m3/h bzw. l/h] *)
    rDensity_kgl        : REAL := 0.0;              (* Dichte [kg/l] *)
    rTemperature_degC   : REAL := 0.0;              (* Kraftstofftemperatur [°C] *)

    (* PROFIBUS PA Qualitäts-Statusbytes (>= 16#80 = Good) *)
    byStatusMassflow    : BYTE := 16#00;
    byStatusVolumeflow  : BYTE := 16#00;
    byStatusDensity     : BYTE := 16#00;
    byStatusTemperature : BYTE := 16#00;

    bMassflowValid      : BOOL := FALSE;            (* Massflow-Status OK *)
    bVolumeflowValid    : BOOL := FALSE;            (* Volumeflow-Status OK *)
    bDensityValid       : BOOL := FALSE;            (* Density-Status OK *)
    bTemperatureValid   : BOOL := FALSE;            (* Temperature-Status OK *)
    bAllValid           : BOOL := FALSE;            (* Alle 4 Messwerte gültig *)
END_VAR

VAR
    dwRawFloat          : DWORD;
    pRealHelper         : POINTER TO REAL;
    rRawValue           : REAL;
END_VAR

IF NOT bEnable THEN
    rMassflow_kgh       := 0.0;
    rVolumeflow         := 0.0;
    rDensity_kgl        := 0.0;
    rTemperature_degC   := 0.0;
    bMassflowValid      := FALSE;
    bVolumeflowValid    := FALSE;
    bDensityValid       := FALSE;
    bTemperatureValid   := FALSE;
    bAllValid           := FALSE;
    RETURN;
END_IF;

pRealHelper := ADR(dwRawFloat);

(* ============================================================================ *)
(* 1. Massflow (Byte 0..3: IEEE-754 Big-Endian Float, Byte 4: Status)           *)
(* ============================================================================ *)
dwRawFloat := SHL(BYTE_TO_DWORD(Data[0]), 24) OR
              SHL(BYTE_TO_DWORD(Data[1]), 16) OR
              SHL(BYTE_TO_DWORD(Data[2]), 8)  OR
              BYTE_TO_DWORD(Data[3]);

rRawValue          := pRealHelper^;
rMassflow_kgh      := rRawValue * 3600.0; (* Umrechnung kg/s in kg/h *)
byStatusMassflow   := Data[4];
bMassflowValid     := (byStatusMassflow AND 16#C0) = 16#80; (* PA Quality Bit: Good *)

(* ============================================================================ *)
(* 2. Volumeflow (Byte 5..8: IEEE-754 Big-Endian Float, Byte 9: Status)         *)
(* ============================================================================ *)
dwRawFloat := SHL(BYTE_TO_DWORD(Data[5]), 24) OR
              SHL(BYTE_TO_DWORD(Data[6]), 16) OR
              SHL(BYTE_TO_DWORD(Data[7]), 8)  OR
              BYTE_TO_DWORD(Data[8]);

rVolumeflow        := pRealHelper^;
byStatusVolumeflow := Data[9];
bVolumeflowValid   := (byStatusVolumeflow AND 16#C0) = 16#80;

(* ============================================================================ *)
(* 3. Density (Byte 10..13: IEEE-754 Big-Endian Float, Byte 14: Status)         *)
(* ============================================================================ *)
dwRawFloat := SHL(BYTE_TO_DWORD(Data[10]), 24) OR
              SHL(BYTE_TO_DWORD(Data[11]), 16) OR
              SHL(BYTE_TO_DWORD(Data[12]), 8)  OR
              BYTE_TO_DWORD(Data[13]);

rDensity_kgl       := pRealHelper^; (* Direkt in kg/l *)
byStatusDensity    := Data[14];
bDensityValid      := (byStatusDensity AND 16#C0) = 16#80;

(* ============================================================================ *)
(* 4. Temperature (Byte 15..18: IEEE-754 Big-Endian Float, Byte 19: Status)     *)
(* ============================================================================ *)
dwRawFloat := SHL(BYTE_TO_DWORD(Data[15]), 24) OR
              SHL(BYTE_TO_DWORD(Data[16]), 16) OR
              SHL(BYTE_TO_DWORD(Data[17]), 8)  OR
              BYTE_TO_DWORD(Data[18]);

rRawValue           := pRealHelper^;
rTemperature_degC   := rRawValue - 273.15; (* Kelvin nach Celsius *)
byStatusTemperature := Data[19];
bTemperatureValid   := (byStatusTemperature AND 16#C0) = 16#80;

(* Gesamt-Gültigkeitsbit *)
bAllValid := bMassflowValid AND bVolumeflowValid AND bDensityValid AND bTemperatureValid;

END_FUNCTION_BLOCK
