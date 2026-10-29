FUNCTION_BLOCK FB_FuelSupply
VAR_INPUT
HW_DI_FuelTank_Empty : BOOL;
SupplyFuelPumpPIDsettings: ARRAY [1..3] OF REAL;
SupplyFuelPump_pressure_tolerance : REAL;
END_VAR

VAR_OUTPUT
HW_DO_EnableAdjPowerSupply : BOOL;
HW_AO_FuelPumpSupplyVoltage : REAL;
END_VAR

VAR_IN_OUT
fbIO_FuelSupply : FuelSupply;
END_VAR

VAR
init : BOOL := FALSE;

max_fuelsupply_pressure : REAL := 10; (*bar*)


Enable : INT;
PID_Controller : Cont_PIDT1_Par;
TS : REAL := 1.0;
T1 : REAL := 0.0;
MaxOutput : REAL := 100.0;
MinOutput : REAL := 0.0;
	
END_VAR

fbIO_FuelSupply.pressure_tolerance := SupplyFuelPump_pressure_tolerance;
ACT_SET_PIDvalues;
IF NOT init THEN
	init := TRUE;
END_IF

(* ENABLE GATE *)

IF NOT fbIO_FuelSupply.enable THEN
	HW_DO_EnableAdjPowerSupply := FALSE;
	HW_AO_FuelPumpSupplyVoltage := 0.0;
	Enable := 0;
	RETURN;
ELSE
	Enable := 3;
END_IF

(* Pumpen anschalten *)
IF fbIO_FuelSupply.start THEN
	HW_DO_EnableAdjPowerSupply := TRUE;
	fbIO_FuelSupply.start := FALSE;
END_IF

(* Pumpen ausschalten *)
IF fbIO_FuelSupply.stop THEN
	HW_DO_EnableAdjPowerSupply := FALSE;
	fbIO_FuelSupply.stop := FALSE;
END_IF

fbIO_FuelSupply.running := HW_DO_EnableAdjPowerSupply;

(* Neuen Sollwert übernehmen *)

IF ABS(fbIO_FuelSupply.SV-fbIO_FuelSupply.SVreq) > 0.01 THEN
	
	IF fbIO_FuelSupply.SVreq < max_fuelsupply_pressure THEN
		fbIO_FuelSupply.SVaccepted := TRUE;
	ELSE
		fbIO_FuelSupply.SVaccepted := FALSE;
	END_IF
	
	IF fbIO_FuelSupply.SVaccepted THEN
		fbIO_FuelSupply.SV := fbIO_FuelSupply.SVreq;
	END_IF
	
END_IF


PID_Controller ( Enable := Enable, (* 0 - Regler deaktivieren;
 											  * 1 - Regler initialisieren (PValue, IValue, DValue und TS neu übernehmen);
 											  * 2 - Regler aktivieren;
 											  * 3 - Regler initialisieren und aktivieren (PValue, IValue, DValue und TS neu übernehmen und regeln)*)
                 
                 SetValue := fbIO_FuelSupply.SV,
                 ActValue := fbIO_FuelSupply.AV,
                 PValue := fbIO_FuelSupply.PID[1],
                 IValue := fbIO_FuelSupply.PID[2],
                 DValue := fbIO_FuelSupply.PID[3],
                 TS := TS,
                 T1 := T1,
                 MaxOutput := MaxOutput,
                 MinOutput := MinOutput );
		
		fbIO_FuelSupply.pid_error     	:= PID_Controller.Error;
		HW_AO_FuelPumpSupplyVoltage    	:= PID_Controller.OutVar;

IF ABS(fbIO_FuelSupply.AV-fbIO_FuelSupply.SV) < fbIO_FuelSupply.pressure_tolerance THEN
	fbIO_FuelSupply.SVreached := TRUE;
ELSE
	fbIO_FuelSupply.SVreached := FALSE;
END_IF

;
END_FUNCTION_BLOCK

ACTIONS
	ACTION ACT_SET_PIDvalues
		IF fbIO_FuelSupply.setPID OR NOT init THEN
			fbIO_FuelSupply.PID[1] := SupplyFuelPumpPIDsettings[1];
			fbIO_FuelSupply.PID[2] := SupplyFuelPumpPIDsettings[2];
			fbIO_FuelSupply.PID[3] := SupplyFuelPumpPIDsettings[3];
			fbIO_FuelSupply.setPID := FALSE;
		END_IF
	END_ACTION


END_ACTIONS