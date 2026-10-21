FUNCTION BH_AlarmBitTOAlarmArray : ARRAY[1..8] OF BOOL
VAR_INPUT
	AlarmInfo : SINT;
END_VAR

VAR

END_VAR

		BH_AlarmBitTOAlarmArray[1] := AlarmInfo.0;
		BH_AlarmBitTOAlarmArray[2] := AlarmInfo.1;
		BH_AlarmBitTOAlarmArray[3] := AlarmInfo.2;
		BH_AlarmBitTOAlarmArray[4] := AlarmInfo.3;
		BH_AlarmBitTOAlarmArray[5] := AlarmInfo.4;
		BH_AlarmBitTOAlarmArray[6] := AlarmInfo.5;
		BH_AlarmBitTOAlarmArray[7] := AlarmInfo.6;
		BH_AlarmBitTOAlarmArray[8] := AlarmInfo.7;
;
END_FUNCTION