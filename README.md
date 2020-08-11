this is `barcode` - my second patch for [norns](https://monome.org/docs/norns/). `barcode` is a noisy looper. it turns loops into hexaphonic orchestrations.

## demo

## requirements

- norns
- line-in

## documentation

press K2 or K3 to record a loop. press again to stop recording.

after recording ends the buffer will be played on six different voices. 

each voice has six parameters: level, pan, rate, reverse, start point, and end point. each of these parameters is modulated by a randomly initialized lfo (that's 36 lfos!). 

each voice is represented by five lines:

- level
- pan 
- rate
- reverse
- start/end points

these five lines are repeated six times (once for each voice).

you can bias the modulation for each of these parameters, by moving E2 to the set of lines for that voice, and then to the line of choice and then use E3 to adjust.

the line at the very top is for the overall level, which can be adjusted with E1.

## thanks

this would not have been possible without the stellar [softcut tutorial](https://monome.org/docs/norns/softcut/) and inspiration from [cranes](https://llllllll.co/t/cranes). 

## license

MIT


