FUNCTION FUN_ScaleRaw_to_Value : REAL
(* This function scales a raw value to a desired range using linear scaling. Input Values have to be of type REAL *)

VAR_INPUT

RawValue : REAL;
ScaledLow: REAL;
ScaledHigh: REAL;
RawLow: REAL;
RawHigh: REAL;

END_VAR

VAR
ScaledValue : REAL;
END_VAR

ScaledValue := ((RawValue - RawLow) / (RawHigh - RawLow)) * (ScaledHigh - ScaledLow ) + ScaledLow;
FUN_ScaleRaw_to_Value := ScaledValue;
END_FUNCTION


