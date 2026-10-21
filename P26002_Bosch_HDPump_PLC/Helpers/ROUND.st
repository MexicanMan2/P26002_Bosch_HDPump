FUNCTION ROUND : REAL
VAR_INPUT
	
	value : REAL;          (* Der zu rundende Wert *)
    decimals : INT;         (* Anzahl der Nachkommastellen (0–4) *)

END_VAR

VAR
	factor : REAL;
	i : INT;

END_VAR


	(* Begrenzung der Nachkommastellen *)
	IF decimals < 0 THEN
	    decimals := 0;
	ELSIF decimals > 4 THEN
	    decimals := 4;
	END_IF
	
	(* Berechnung des Faktors *)
	FOR i := 1 TO decimals DO
	    factor := factor * 10.0;
	END_FOR

	
	(* Rundung *)
	ROUND := DINT_TO_REAL(REAL_TO_DINT(value * factor + 0.5)) / factor;
	
END_FUNCTION