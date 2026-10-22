FUNCTION_BLOCK FB_AutomaticOperation
VAR_INPUT
	Enable  : BOOL;
    Start   : BOOL;
    Stop    : BOOL;
    Cancel  : BOOL;
    Reset   : BOOL;
END_VAR

VAR_OUTPUT
	State   : state_op_manager; (* OP_Settle und OP_Hold brauchen wir in diesem Projekt nicht *)
    Busy    : BOOL;
    Done    : BOOL;
    Error   : BOOL;
    ErrMsg	: STRING(255);
END_VAR

VAR
	NextState  : state_op_manager;
    LastState  : state_op_manager;
    
	bEntry			: BOOL := TRUE;
	bInitDone       : BOOL := FALSE;
END_VAR

(* ----------------------------- *)
(* -------- Enable-Gate -------- *)
(* ----------------------------- *)
IF NOT Enable OR system.state = SYS_ERROR OR system.state = SYS_STANDBY THEN
	bInitDone := FALSE;
    State     := OP_INIT;
    LastState := OP_INIT;
    Busy      := FALSE;
    Done      := FALSE;
    Error     := FALSE;
    User.Input.start := FALSE;
    RETURN;
END_IF;

(* ------------------------------------------------ *)
(* Default assignments                              *)
(* ------------------------------------------------ *)
NextState := State;
Busy  := FALSE;
Done  := FALSE;
Error := FALSE;

(* ------------------------------------------------ *)
(* Entry-Erkennung                                  *)
(* ------------------------------------------------ *)
bEntry := (State <> LastState);

(* ------------------------------------------------ *)
(* State Machine                                    *)
(* ------------------------------------------------ *)
CASE State OF
	
	OP_INIT:
	    Busy := FALSE;
	    
	    IF NOT bInitDone THEN
	    
	    ; (* Alle Infos einlesen, ggf Geräte verbinden, Geräte-Status prüfen... *)
	    
	    bInitDone := TRUE;
	    END_IF
	    
	    IF bInitDone THEN
	        NextState := OP_IDLE;
	        User.Output.operation_status_msg := 'INFO: OP Manager initialized.';
	    END_IF
	    
    OP_IDLE:
	    Busy := FALSE;
(*				Done := FALSE; *)
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
	    
    OP_EXECUTE:
	    Busy := TRUE;
	    Done := FALSE;
	    Error := FALSE;
	
	OP_FINISHED:
	    Busy := FALSE;
	    Done := TRUE;
	    Error := FALSE;
	
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
IF User.Input.cancel THEN
    IF State <> OP_INIT AND State <> OP_ERROR THEN
        NextState := OP_FINISHED;
        User.Input.start := FALSE;
        User.Input.continuous := FALSE;
    ELSIF State = OP_ERROR_SHUTDOWN THEN
    	NextState := OP_ERROR;
    	User.Input.start := FALSE;
        User.Input.continuous := FALSE;
    END_IF
END_IF

IF User.Input.skipOP THEN
    IF State <> OP_INIT AND State <> OP_ERROR THEN
        NextState := OP_FINISHED;
        User.Input.start := TRUE;
        User.Input.continuous := TRUE;
    END_IF
END_IF

(* ------------------------------------------------ *)
(* ---------- Subsystem Error Detection ----------- *)
(* ------------------------------------------------ *)
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
	;
	END_ACTION
	
END_ACTIONS
