(******************************************************************************
Description: Blink Takt Generator

Generates a symmetrical blinking signal using internal TON and TP timers.
The blink period is defined via the input time and split into equal ON/OFF phases.
A rising edge detector ensures clean toggling of the blink signal.

Input:
  - IN_period : TIME
      Total blink period (e.g. T#1s for 1 Hz blink).
      The signal will be HIGH for half the period and LOW for the other half.

Output:
  - Out_BlinkTakt : BOOL
      The generated blinking signal with a 50% duty cycle.

Internal:
  - HalfTime : TIME
      Half of the total blink period (IN_period / 2).
	  Defines both the ON and OFF duration to achieve a symmetrical 50 % duty cycle.
  - BlinkTON : TON
      On-delay timer used as the periodic time base.
	  The timer measures each half-period and signals its completion via Q, upon which the blink state is toggled and the timer cycle restarts.
  - BlinkState : BOOL
	  Internal state variable holding the current blink state.
	  The value is toggled once every half-period when BlinkTON.Q becomes TRUE and directly drives the output Out_BlinkTakt.

Return: Output variable `Out_BlinkTakt` provides the blinking signal.
******************************************************************************)

FUNCTION_BLOCK FB_BlinkTakt
VAR_INPUT
IN_period : TIME;
END_VAR

VAR_OUTPUT
Out_BlinkTakt : BOOL;
END_VAR


VAR
    
    HalfTime : TIME;
    BlinkTON : TON;
    BlinkState : BOOL := FALSE;

END_VAR


HalfTime := IN_period / 2;

BlinkTON(IN := NOT BlinkTON.Q, PT := HalfTime);


IF BlinkTON.Q THEN
    BlinkState := NOT BlinkState;
END_IF;


Out_BlinkTakt := BlinkState;

END_FUNCTION_BLOCK