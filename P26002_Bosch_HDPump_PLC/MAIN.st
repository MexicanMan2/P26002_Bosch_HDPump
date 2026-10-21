PROGRAM MAIN

(*
[ ] Mapping MFC
[ ] Mapping Heaters
[x] Mapping Valves
[x] Evaporators
[x] Mapping Evaporators
[x] Pump
[x] Potentiostat
[ ] Safety
[x] Valves
[ ] UserInOut / PanelStatusOutput
[ ] UserSettings
[x] CondensationColumn LevelManagement

*)
VAR
next_state : state_system;
last_state : state_system;

(* GLOBAL ERROR HANDLING *)
was_error: BOOL := FALSE;
ErrorDelayTimer : TON;         (* Delay for Error Detection *)
TriggerTime : TIME := T#1s;
ResetTrigger : TP;
StopTrigger : TP;
ALARM_ARRAY: ARRAY [1..20] OF BOOL;
WARNING_ARRAY: ARRAY [1..30] OF BOOL;
i : INT; (*Iteration Variable*)

(* Reset Device Errors *)
resetMfCError : BOOL;
resetEvapError : BOOL;

END_VAR

ACT_EmgStop_bySoftware;
ACT_READ_SafetyStatus;
Act_UserOutput;

ACT_StateMachine;

END_PROGRAM

ACTIONS

ACTION ACT_InitSystem
User.Settings := Retain_Settings;
;
END_ACTION

ACTION ACT_StateMachine

system.state := next_state;

	CASE system.state OF
		SYS_STANDBY:							
						IF system.alarm OR system.error THEN
							next_state := SYS_ERROR;
							RETURN;
						END_IF
						
						IF NOT system.is_init THEN
							ACT_InitSystem;
							system.is_init := TRUE;
						END_IF;
						
						IF User.Input.OperationModeReq THEN
							next_state := SYS_MANUAL;
						END_IF
						
		SYS_ERROR :								
						ResetTrigger(IN:= User.Input.reset_Error_byUser, PT:= TriggerTime);
						
						IF  ResetTrigger.Q THEN
							reset_EmgStop := TRUE;
							User.Input.reset_Error_byUser := FALSE;
						END_IF
						
						RETURN;
		
		SYS_AUTO_BUSY,SYS_AUTO_READY : next_state := SYS_STANDBY; (* Not defined *)
		
		SYS_MANUAL :
						
						IF system.alarm OR system.error THEN
							next_state := SYS_ERROR;
							RETURN;
						END_IF
						
						IF User.Input.StandbyModeReq THEN
							next_state := SYS_STANDBY;
							RETURN;
						END_IF
		;
	ELSE
		next_state := SYS_ERROR; (* Other States not allowed!!! *)
		system.status_msg := 'ERROR: State Request NOT allowed!';
	END_CASE

(* Global User Input Reset *)
User.Input.reset_Error_byUser := FALSE;
User.Input.StandbyModeReq := FALSE;
User.Input.OperationModeReq := FALSE;

last_state := system.state;
END_ACTION

ACTION Act_UserOutput
		
		Retain_Settings := User.Settings; (* Backup in Retain Variable *)
		
		User.Output.SystemState := system;

		
	END_ACTION

ACTION ACT_EmgStop_bySoftware
	StopTrigger(IN:= User.Input.EmgStop_Req_byUser, PT:= TriggerTime);
	req_EmgStop_bySoftware := StopTrigger.Q; 

	IF req_EmgStop_bySoftware THEN
		User.Input.EmgStop_Req_byUser := FALSE;
	END_IF
	;
END_ACTION

ACTION ACT_READ_SafetyStatus (* Wird direkt im Safetyprogramm gemappt *)

		ALARM_ARRAY[1] := system.ALARM_SAI_DiagnosticError;
		ALARM_ARRAY[2] := system.ALARM_GASALARM_H2_ST_STBQ2;
		ALARM_ARRAY[3] := system.ALARM_GASALARM_H2_CT_STBQ1;
		ALARM_ARRAY[4] := system.ALARM_NotAusTaster_1_STFS1;
		ALARM_ARRAY[5] := system.ALARM_NotAusTaster_2_BPSF1;
		ALARM_ARRAY[6] := system.ALARM_EmgStop_bySoftware_activated;
		ALARM_ARRAY[7] := system.ALARM_N2Supply_STBP1;
		ALARM_ARRAY[8] := system.ALARM_HeaterLimit_T_STBT1;
		ALARM_ARRAY[9] := system.ALARM_HeaterLimit_T_STBT2;
		ALARM_ARRAY[10] := system.ALARM_NotAusTaster_1_STFS1_Discrepancy;
		ALARM_ARRAY[11] := system.ALARM_NotAusTaster_2_BPSF1_Discrepancy;
		ALARM_ARRAY[12] := system.ALARM_QA1_Discrepancy;
		ALARM_ARRAY[13] := system.ALARM_QA2_Discrepancy;
		ALARM_ARRAY[14] := system.ALARM_Draeger_Fault;
		
		
		FOR i:= 1 TO 20 DO
			IF ALARM_ARRAY[i] THEN
				system.alarm := TRUE;
			END_IF
		END_FOR

				
	END_ACTION

END_ACTIONS