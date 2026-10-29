PROGRAM SUBP_SignalLights
VAR


END_VAR


ACT_StateLights;
(* SUBP_HWmapping_Lights; *) (* KEINE HW vorhanden*)

END_PROGRAM

ACTIONS
(* Bedienpanel: alles gleiche Schriftgröße *)
(*	- NOT-Aus --> NOT-Aus *)
(*	- rot --> Alarm \ Reset *)
(*	- gelb --> Betrieb \ Start *)
(*	- grün --> Stand-BY \ Stop *)
(*	ggf. vor Befehl Symbole setzen (Lampe + Hand o.Ä.) *)
(*	Kommentare Lukas: *)
(*		Symbole vor den Text wären sinnvoll *)
(*		rot --> Alarm / Reset (damit sind Anzeige und Funktionalität auf einem Leuchttaster) *)
(*			konstant: Warnung *)
(*			blinkend: Alarm *)
(*		gelb --> Betrieb / Start - startet eine vordefinierte Sequenz im Automatikmodus *)
(*			konstant: Betrieb - Eingeregelt *)
(*			blinkend: Betrieb - transient oder Manueller Modus *)
(*		grün --> Standby / Softstop - In den Standby fahren, inkl CoolDown und N2-Spülen  *)
(*			konstant: Alles sicher, Prüfstand tut nix *)
(*			blinkend: Heizungen / Ventile bestromt *)
			
	 ACTION ACT_StateLights
	 	CASE system.state OF
	 	
	    1: (* ERROR *)

	        User.Output.Ampel_rot := TRUE;
	        User.Output.Ampel_rot_blink := FALSE;
	        User.Output.Ampel_gelb := FALSE;
	        User.Output.Ampel_gelb_blink := FALSE;
	        User.Output.Ampel_gruen := FALSE;
	        User.Output.Ampel_gruen_blink := FALSE;
	        
	    0: (* Standby *)
	
	    	User.Output.Ampel_rot := FALSE;
	        User.Output.Ampel_rot_blink := FALSE;
	        User.Output.Ampel_gelb := FALSE;
	        User.Output.Ampel_gelb_blink := FALSE;
	        User.Output.Ampel_gruen := TRUE;
	        User.Output.Ampel_gruen_blink := FALSE;
	        
	    2,3: (* Automatic *)
	    	CASE AutomaticOperation.State OF
	    		OP_INIT,OP_IDLE:

							        User.Output.Ampel_rot := FALSE;
							        User.Output.Ampel_rot_blink := FALSE;
							        User.Output.Ampel_gelb := FALSE;
							        User.Output.Ampel_gelb_blink := FALSE;
							        User.Output.Ampel_gruen := FALSE;
							        User.Output.Ampel_gruen_blink := TRUE;
	        
		    	OP_HOLD,OP_FINISHED:
							        
							        User.Output.Ampel_rot := FALSE;
							        User.Output.Ampel_rot_blink := FALSE;
							        User.Output.Ampel_gelb := TRUE;
							        User.Output.Ampel_gelb_blink := FALSE;
							        User.Output.Ampel_gruen := FALSE;
							        User.Output.Ampel_gruen_blink := FALSE;
	        
			    OP_PREP, OP_EXECUTE, OP_WAIT_SETTLED:
							        
							        User.Output.Ampel_rot := FALSE;
							        User.Output.Ampel_rot_blink := FALSE;
							        User.Output.Ampel_gelb := FALSE;
							        User.Output.Ampel_gelb_blink := TRUE;
							        User.Output.Ampel_gruen := FALSE;
							        User.Output.Ampel_gruen_blink := FALSE;
		    END_CASE
	            
	    4: (* Manual Operation Mode *)
	        
	        User.Output.Ampel_rot := FALSE;
	        User.Output.Ampel_rot_blink := FALSE;
	        User.Output.Ampel_gelb := FALSE;
	        User.Output.Ampel_gelb_blink := TRUE;
	        User.Output.Ampel_gruen := FALSE;
	        User.Output.Ampel_gruen_blink := FALSE;
		     
		END_CASE
		
		IF system.state <> 1 AND system.warning THEN
			User.Output.Ampel_rot_blink := TRUE;
		END_IF
	 END_ACTION

END_ACTIONS