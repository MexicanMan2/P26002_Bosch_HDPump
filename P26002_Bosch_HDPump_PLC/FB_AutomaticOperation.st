FUNCTION_BLOCK FB_AutomaticOperation
VAR_INPUT
	system_state : System;
	Enable  : BOOL;
    Stop    : BOOL;
    Reset   : BOOL;
    sequence_active : BOOL;
    
    coldStart_oil_pressure: REAL := 1.8; (* bar *)
	coldStart_oil_min_tempterature: REAL := 50; (* °C *)
	coldStart_fuelsupply_pressure: REAL := 2; (* bar *)
	coldStart_fuelsupply_min_tempterature: REAL := 50; (* °C *)
	coldStart_RPM_settings: REAL := 2000; 
	
	normalOperation_oil_pressure: REAL := 2.5;(* bar *)
END_VAR

VAR_OUTPUT
	State   : state_op_manager; (* OP_Settle und OP_Hold brauchen wir in diesem Projekt nicht *)
    Busy    : BOOL;
    Done    : BOOL;
    Error   : BOOL;
    ErrMsg	: STRING(255);
    
    (* ----------------------------- *)
	(* ----- Sequence Control ------ *)
	(* ----------------------------- *)
    
    start_sequence: BOOL;
    stop_sequence: BOOL;
    coldStart_RPM : REAL;
    
     (* --- Konfiguration --- *)
    current_OP: OPoint;
    
END_VAR

VAR_IN_OUT
	IO_User : User_InOut;
	IO_Thermostat : Thermostat;
	IO_OilConditioning: OilConditioning;
	IO_FuelSupply: FuelSupply;
	IO_GlobalOP_List : ARRAY[0..10] OF OPoint;
END_VAR

VAR
	NextState  : state_op_manager;
    LastState  : state_op_manager;
    
    rpm_rampup: FB_RampTON;
    rpm_rampup_time: TIME := T#2m;
    rpm_rampup_Done: BOOL;
    
    prep_settle_timer: TON;
    prep_settle_time: TIME := T#60s;
    
	bEntry			: BOOL := TRUE;
	bInitDone       : BOOL := FALSE;
END_VAR


(* ----------------------------- *)
(* -------- Enable-Gate -------- *)
(* ----------------------------- *)
IF NOT Enable OR system_state.state = SYS_ERROR OR system_state.state = SYS_STANDBY THEN
	bInitDone := FALSE;
    State     := OP_INIT;
    LastState := OP_INIT;
    Busy      := FALSE;
    Done      := FALSE;
    Error     := FALSE;
    IO_User.Input.start := FALSE;
    RETURN;
END_IF;

(* ------------------------------------------------ *)
(* Default assignments                              *)
(* ------------------------------------------------ *)
NextState := State;
Busy  := FALSE;
Done  := FALSE;
Error := FALSE;
coldStart_RPM := 0.0;
rpm_rampup.bExecute := FALSE;
IO_Thermostat.enable := FALSE;
IO_OilConditioning.enable := FALSE;
IO_FuelSupply.enable := FALSE;

(* ------------------------------------------------ *)
(* Entry-Erkennung                                  *)
(* ------------------------------------------------ *)
bEntry := (State <> LastState);

(* ------------------------------------------------ *)
(* State Machine                                    *)
(* ------------------------------------------------ *)
CASE State OF
	
	OP_INIT:
	    Busy  := FALSE;
		Done  := FALSE;
		Error := FALSE;
	    
	    IF NOT bInitDone THEN
	    
	    ; (* Alle Infos einlesen, ggf Geräte verbinden, Geräte-Status prüfen... *)
	    
	    bInitDone := TRUE;
	    END_IF
	    
	    IF bInitDone THEN
	        NextState := OP_IDLE;
	        IO_User.Output.operation_status_msg := 'INFO: OP Manager initialized.';
	    END_IF
	    
    OP_IDLE:
	    Busy  := FALSE;
		Done  := FALSE;
		Error := FALSE;
		
    	; (* Warten auf neue Startbedingungen *)
    	(* ------------------------------------------ *)
	    (* Startbedingung prüfen                      *)
	    (* ------------------------------------------ *)
	    Act_CheckStartConditions;
	
    
    OP_PREP:
    	Busy := TRUE;
	    Done := FALSE;
	    Error := FALSE;
	    
	    IO_Thermostat.enable := TRUE;
		IO_OilConditioning.enable := TRUE;
		IO_FuelSupply.enable := TRUE;
	    
	    (* Thermostat an *)
	    IO_Thermostat.target_setpoint := current_OP.Fuel_temperature;
	    IO_Thermostat.start := TRUE;
	    
	    (* Ölkonditionierung an *)
	    IF (IO_OilConditioning.actualOil_temperature < coldStart_oil_min_tempterature+5) THEN
	    	IO_OilConditioning.setOil_pressure := coldStart_oil_pressure;
	    ELSE
	    	IF current_OP.Oil_pressure > normalOperation_oil_pressure THEN
	    		IO_OilConditioning.setOil_pressure := current_OP.Oil_pressure;
	    	ELSE
	    		IO_OilConditioning.setOil_pressure := normalOperation_oil_pressure; (* Agleich OP-Vorgabe *)
	    	END_IF
	    END_IF
	    
	    IO_OilConditioning.setOil_temperature := current_OP.Oil_temperature; (* Wie bekomme ich die Temperatur ins ÖL? *)
	    
	    IO_OilConditioning.start := TRUE;
	    
	    (* Ramp up RPM *)
	    IF bEntry THEN
	    	rpm_rampup(bExecute := FALSE); (* Einmal zurücksetzen *)
	    ELSE
			rpm_rampup(
			 	bExecute := TRUE,
			 	fStartVal := 0.0,
			 	fTargetVal := coldStart_RPM_settings,
			 	tRampTime := rpm_rampup_time,
			 	fCurrentVal => coldStart_RPM,
			 	bDone => rpm_rampup_Done
			);
		END_IF
	    
	    IF IO_Thermostat.SVreached AND
	    	IO_OilConditioning.pressure_SVreached AND
	    	IO_OilConditioning.temperature_SVreached THEN
	    	
	    	prep_settle_timer.IN := TRUE;
	    END_IF
	    
	    IF prep_settle_timer.Q THEN
	    	IO_FuelSupply.SV := current_OP.Fuel_supply_pressure;
	    	IO_FuelSupply.start := TRUE;
	    END_IF
	    
	    IF IO_Thermostat.SVreached AND
	    	IO_OilConditioning.pressure_SVreached AND
	    	IO_OilConditioning.temperature_SVreached AND
	    	IO_FuelSupply.SVreached AND
	    	rpm_rampup_Done THEN
	    	
	    	NextState := OP_EXECUTE;
	    END_IF 
	    
	    
    OP_EXECUTE:
	    Busy := TRUE;
	    Done := FALSE;
	    Error := FALSE;
	    
	    IO_Thermostat.enable := TRUE;
		IO_OilConditioning.enable := TRUE;
		IO_FuelSupply.enable := TRUE;
		
	    (* Benzin-Versorgung an*)
	    (* Nockenwellenantrieb nach Drehzahlvorgabe fahren*)
	
	OP_FINISHED:
	    Busy := FALSE;
	    Done := TRUE;
	    Error := FALSE;
	    
	    IO_Thermostat.enable := TRUE;
		IO_OilConditioning.enable := TRUE;
(*		IO_FuelSupply.enable := TRUE; *)
	        
	    (* Benzin-Versorgung aus *)
	    IO_FuelSupply.stop := TRUE;
	    
	    (* Nockenwellenantrieb aus*)
	    
	    IF IO_User.Input.continuous THEN
	    	Act_CheckStartConditions;
	    ELSE
	    	(*Cooldown: Thermostat aus, Ölkonditionierung aus*);
	    	IO_Thermostat.stop := TRUE;
	    	IO_OilConditioning.stop := TRUE;
	    	
	    END_IF
	
	OP_ERROR_SHUTDOWN:
	    Error := TRUE;
	    Busy := TRUE;
	
	OP_ERROR:
	    Error := TRUE;
	    Done := TRUE;
	
END_CASE;

(* ------------------------------------------------ *)
(* Global transitions                               *)
(* ------------------------------------------------ *)
IF IO_User.Input.cancel THEN
    IF State <> OP_INIT AND State <> OP_ERROR THEN
        NextState := OP_FINISHED;
        IO_User.Input.start := FALSE;
        IO_User.Input.continuous := FALSE;
    ELSIF State = OP_ERROR_SHUTDOWN THEN
    	NextState := OP_ERROR;
    	IO_User.Input.start := FALSE;
        IO_User.Input.continuous := FALSE;
    END_IF
END_IF

IF IO_User.Input.skipOP THEN
    IF State <> OP_INIT AND State <> OP_ERROR THEN
        NextState := OP_FINISHED;
        IO_User.Input.start := TRUE;
        IO_User.Input.continuous := TRUE;
    END_IF
END_IF

(* ------------------------------------------------ *)
(* ---------- Subsystem Error Detection ----------- *)
(* ------------------------------------------------ *)

(* FÜR BOSCHPRÜFSTAND: MFC FEHLER, FU Fehler, Validierungs Probleme?*)

(* IF 	(SUBP_MfcControl.ErrorDetected OR *)
(*	SUBP_HeaterControl.ErrorDetected) OR *)
(*	system.ALARM_VORALARM_H2_CT_STBQ1 AND *)
(*	State <> OP_ERROR_SHUTDOWN AND *)
(*	State <> OP_ERROR *)
(* THEN *)
(*			NextState := OP_ERROR_SHUTDOWN; *)
(*			IF SUBP_MfcControl.ErrorDetected THEN *)
(*				ErrMsg := SUBP_MfcControl.ErrMsg; *)
(*			ELSIF SUBP_HeaterControl.ErrorDetected THEN *)
(*				ErrMsg := SUBP_HeaterControl.ErrMsg; *)
(*			ELSIF system.ALARM_VORALARM_H2_CT_STBQ1 THEN *)
(*				ErrMsg := 'H2 Gas PreAlarm > 5% LowerExplosionLimit - ERROR_SHUTDOWN triggered!'; *)
(*			ELSE *)
(*				ErrMsg := 'Unknown Error detected'; *)
(*			END_IF *)
(*			Act_StateUpdate; *)
(*			RETURN; *)
(* END_IF *)

(* ------------------------------------------------ *)
(* --------- Aktualisierung Statemachine ---------- *)
(* ------------------------------------------------ *)

Act_StateUpdate;

 (* ====== PROGRAMM ENDE ====== *)
END_FUNCTION_BLOCK

ACTIONS
	ACTION Act_StateUpdate
		(* ------------------------------------------------ *)
		(* State update                                     *)
		(* ------------------------------------------------ *)
		LastState := State;
		IF NextState <> State THEN
		    State := NextState;
		END_IF;
	END_ACTION
	
	ACTION Act_CheckStartConditions
		
		current_OP := IO_GlobalOP_List[1]; (* Aktuell keine OP-Liste unterstützt *)
		
		IF current_OP.ProfileConfig.bDataReady AND NOT current_OP.processed THEN
			current_OP.ProfileConfig.bProfileValid := TRUE;
			NextState := OP_PREP;
		END_IF
	
	END_ACTION
	
END_ACTIONS
