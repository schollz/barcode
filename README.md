# barcode

![barcode](https://user-images.githubusercontent.com/6550035/89963709-3031cb80-dbfd-11ea-8aa2-486e7f2e10bf.gif)

this is `barcode` - my second patch for [norns](https://monome.org/docs/norns/). `barcode` replays a buffer six times, at different levels & pans & rates & positions, modulated by lfos on every parameter.

## demo

<p align="center"><a href="https://www.instagram.com/p/CDxUwsSh7oP/?utm_source=ig_web_button_share_sheet"><img src="https://user-images.githubusercontent.com/6550035/89964863-1f368980-dc00-11ea-87f4-ea58cf29d40d.png" alt="Demo of playing" width=80%></a></p>

## requirements

- norns
- line-in

## documentation

- hold K1 to shift
- K2 to pauses LFOs
- K3 starts recording
- any key stops recording
- shift+K2 switches buffer
- shift+K3 clears
- E1 changes output/rec levels
- E2 dials through parameters
- E3 adjusts current parameter

after recording finishes, the corresponding buffer will be played on six different voices. 

each voice has six parameters: level, pan, rate, reverse, start point, and end point. each of these parameters is modulated by a randomly initialized lfo (that's 36 lfos!). at this point, the lfos cannot be modulated except by changing the code.

in the ui, the parameters of the voices are represented as six groups of five lines. each group of lines corresponds to one voice. the order of the five lines corresponds to the parameters:

1. level
2. pan 
3. rate
4. reverse
5. start/end points

you can bias the modulation for any parameter using E2 to move the corresponding line (a parameter for a voice) and then adjusting with E3.

the line at the very top is for the overall level, which can be adjusted with E1.

## my other patches

- [blndr](https://github.com/schollz/blndr): a quantized delay for monomes norns with time morphing
- [oooooo](https://github.com/schollz/oooooo): 6 x digital tape loops.
- [clcks](https://github.com/schollz/clcks): a tempo-locked repeater for monome norns


## thanks

this would not have been possible without the stellar [softcut tutorial](https://monome.org/docs/norns/softcut/) and inspiration from [cranes](https://llllllll.co/t/cranes). 

## license

MIT


### new in v0.4

- ui: bigger, scrolling highlights parameters
- ui: better messages, removed redundancies
- ui: record with just pressing E3
- bug fix: disallow rate of 0
