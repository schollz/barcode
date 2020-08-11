this is `barcode` - my second patch for [norns](https://monome.org/docs/norns/). `barcode` is a noisy looper. it turns loops into hexaphonic orchestrations.

## demo

## requirements

- norns
- line-in

## documentation

press K2 (buffer 1) or K3 (buffer 2) to record a loop. press again to stop recording.

after recording finishes, the corresponding buffer will be played on six different voices. 

each voice has six parameters: level, pan, rate, reverse, start point, and end point. each of these parameters is modulated by a randomly initialized lfo (that's 36 lfos!). 

in the ui, the parameters of the voices are represented as six groups of five lines. each group of lines corresponds to one voice. the order of the five lines corresponds to the parameters:

1. level
2. pan 
3. rate
4. reverse
5. start/end points

you can bias the modulation for any parameter using E2 to move the corresponding line (a parameter for a voice) and then adjusting with E3.

the line at the very top is for the overall level, which can be adjusted with E1.

## thanks

this would not have been possible without the stellar [softcut tutorial](https://monome.org/docs/norns/softcut/) and inspiration from [cranes](https://llllllll.co/t/cranes). 

## license

MIT


