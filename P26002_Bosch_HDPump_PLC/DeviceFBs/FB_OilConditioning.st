FUNCTION_BLOCK FB_OilConditioning
VAR_INPUT
HW_AI_OilTemperature : REAL;
HW_AI_OilPressure : REAL;
OilConditioning_pressure_tolerance : REAL;
OilConditioning_temperature_tolerance : REAL;
END_VAR

VAR_OUTPUT
HW_AO_OilPressure : REAL;
HW_DO_EnableOilFan: BOOL;
HW_DO_EnableOilConditioning: BOOL;
END_VAR

VAR_IN_OUT
fbIO_OilConditioning : OilConditioning;
END_VAR

VAR
max_oil_pressure : REAL := 10; (* bar *)
max_oil_temperature : REAL := 90; (* °C)*)
END_VAR

fbIO_OilConditioning.temperature_tolerance      := OilConditioning_temperature_tolerance;
fbIO_OilConditioning.pressure_tolerance         := OilConditioning_pressure_tolerance;
		
fbIO_OilConditioning.actualOil_pressure := HW_AI_OilPressure;
fbIO_OilConditioning.actualOil_temperature := HW_AI_OilTemperature;


(* ENABLE GATE *)

IF NOT fbIO_OilConditioning.enable THEN
	HW_DO_EnableOilConditioning := FALSE;
	HW_DO_EnableOilFan := FALSE;
	HW_AO_OilPressure := 0.0;
	fbIO_OilConditioning.pressure_SVaccepted := FALSE;
	fbIO_OilConditioning.temperature_SVaccepted := FALSE;
	RETURN;
END_IF

(* Pumpen anschalten *)
IF fbIO_OilConditioning.start THEN
	HW_DO_EnableOilConditioning := TRUE;
ELSE
	HW_DO_EnableOilConditioning := FALSE;
END_IF

(* Lüfter anschalten *)
IF (fbIO_OilConditioning.actualOil_temperature - fbIO_OilConditioning.setOil_temperature) > 3*fbIO_OilConditioning.temperature_tolerance 
	OR fbIO_OilConditioning.actualOil_temperature > max_oil_temperature THEN
	HW_DO_EnableOilFan := TRUE;
ELSE
	HW_DO_EnableOilFan := FALSE;
END_IF

(* Neuen Sollwert übernehmen *)

IF ABS(fbIO_OilConditioning.setOil_pressure-HW_AO_OilPressure) > 0.01 THEN
	
	IF fbIO_OilConditioning.setOil_pressure < max_oil_pressure THEN
		fbIO_OilConditioning.pressure_SVaccepted := TRUE;
	ELSE
		fbIO_OilConditioning.pressure_SVaccepted := FALSE;
	END_IF
	
	IF fbIO_OilConditioning.pressure_SVaccepted THEN
		HW_AO_OilPressure := fbIO_OilConditioning.setOil_pressure;
	END_IF
	
END_IF
	
IF fbIO_OilConditioning.setOil_temperature < max_oil_temperature THEN
	fbIO_OilConditioning.temperature_SVaccepted := TRUE;
ELSE
	fbIO_OilConditioning.temperature_SVaccepted := FALSE;
END_IF
	

IF ABS(fbIO_OilConditioning.actualOil_temperature-fbIO_OilConditioning.setOil_temperature) < fbIO_OilConditioning.temperature_tolerance THEN
	fbIO_OilConditioning.temperature_SVreached := TRUE;
ELSE
	fbIO_OilConditioning.temperature_SVreached := FALSE;
END_IF

IF ABS(fbIO_OilConditioning.actualOil_pressure-fbIO_OilConditioning.setOil_pressure) < fbIO_OilConditioning.pressure_tolerance THEN
	fbIO_OilConditioning.pressure_SVreached := TRUE;
ELSE
	fbIO_OilConditioning.pressure_SVreached := FALSE;
END_IF

;
END_FUNCTION_BLOCK


(* start:	BOOL; *)
(* stop:	BOOL; *)
(* enabled: BOOL; *)
(*  *)
(* setOil_temperature: REAL; *)
(* setOil_pressure: REAL; *)
(*  *)
(* actualOil_temperature: REAL; *)
(* actualOil_pressure: REAL; *)
(*  *)
(* temperature_tolerance      : REAL := 2; *)
(* pressure_tolerance         : REAL := 0.5; *)
(*  *)
(* temperature_SVaccepted           : BOOL := FALSE; *)
(* temperature_SVreached            : BOOL := FALSE; *)
(*  *)
(* pressure_SVaccepted           : BOOL := FALSE; *)
(* pressure_SVreached            : BOOL := FALSE; *)