(********************************************************************************
 * FUNCTION_BLOCK: FB_ProfibusDrive
 * 
 * Beschreibung:
 *   Profibus-Anbindung für Frequenzumrichter nach Profidrive Profil.
 *   - Steuerwort 1 (STW1): 16#047F bei Freigabe, 16#047E bei Stillstand
 *   - Drehzahlsollwert (NSOLL_A): Skaliert auf 16384 (16#4000) = 100% Bezugsdrehzahl
 ********************************************************************************)
FUNCTION_BLOCK FB_ProfibusDrive
VAR_INPUT
    bEnable         : BOOL;
    fRpmSetpoint    : REAL;
    fReferenceRpm   : REAL; (* 100% Bezugsdrehzahl, z.B. 3000.0 U/min *)
END_VAR
VAR_OUTPUT
    nControlWord    : WORD; (* STW1 an Profibus *)
    nSpeedSetpoint  : INT;  (* NSOLL_A an Profibus (-16384 .. +16384) *)
END_VAR
VAR
    fNorm           : REAL;
END_VAR

IF bEnable THEN
    (* Standardtelegramm 1: Betrieb freigegeben (0x047F) *)
    nControlWord := 16#047F;

    IF fReferenceRpm > 0.0 THEN
        fNorm := (fRpmSetpoint / fReferenceRpm) * 16384.0;

        (* Begrenzung auf INT-Wertebereich *)
        IF fNorm > 32767.0 THEN fNorm := 32767.0; END_IF;
        IF fNorm < -32768.0 THEN fNorm := -32768.0; END_IF;

        nSpeedSetpoint := REAL_TO_INT(fNorm);
    ELSE
        nSpeedSetpoint := 0;
    END_IF;
ELSE
    (* Stillstand / Einschaltbereit (0x047E) *)
    nControlWord   := 16#047E;
    nSpeedSetpoint := 0;
END_IF;

END_FUNCTION_BLOCK
