-- hexaphonic v0.1
-- 6 voice looper
--      __
--  __/   \__
-- /  \__/   \
-- \__/  \__/
-- /  \__/   \
-- \__/  \__/
--   \__/
--
-- k2/k3 steps through voices
-- k2+k3 toggles buffers
-- k1+k2 records buffer 1
-- k1+k3 records buffer 2
-- e1 adjusts start position
-- k1+e1 adjust end position
-- e2 adjusts level
-- k1+e2 adjusts lfo
-- e3 adjusts playback speed
-- k1+e3 adjusts pan

shift=0
shift23=0
state_recording=0
state_v=1
state_buffer=1
state_lfo_time=0
voice={}
rates={-4,-2,-1,-0.5,-.25,0,0.25,0.5,1,2,4}

const_lfo_inc=0.25
maxbuffer=15

function init()
  for i=1,6 do
    -- TODO: try making lfo_offset=math.random(0,60)
    voice[i]={level=0,pan=0,rate=9,ls=0,le=3,lfo=0,lfo_offset=0,buffer=1}
  end
  voice[1].level=1
  voice[2].rate=2
  voice[3].rate=3
  voice[4].rate=8
  voice[5].rate=10
  voice[6].rate=11
  -- send audio input to softcut input
  audio.level_adc_cut(1)
  softcut.buffer_clear()
  for i=1,6 do
    softcut.enable(i,1)
    softcut.buffer(i,1)
    softcut.loop(i,1)
    softcut.position(i,1)
    softcut.play(i,1)
    softcut.loop_start(i,voice[i].ls+1)
    softcut.loop_end(i,voice[i].le+1)
    softcut.level(i,voice[i].level)
    softcut.rate(i,rates[voice[i].rate])
    softcut.pan(i,voice[i].pan)
    softcut.rate_slew_time(i,0.5)
    softcut.level_slew_time(i,0.5)
    softcut.pan_slew_time(i,0.5)
  end
  -- set input rec level: input channel, voice, level
  softcut.level_input_cut(1,1,1.0)
  softcut.level_input_cut(2,1,1.0)
  -- set voice 1 record level
  softcut.rec_level(1,1.0)
  -- set voice 1 pre level
  softcut.pre_level(1,1.0)
  -- set record state of voice 1 to 1
  softcut.rec(1,0)
  
  lfo=metro.init()
  lfo.time=const_lfo_inc
  lfo.count=-1
  lfo.event=update_lfo
  lfo:start()
end

function update_lfo()
  -- update lfo counter
  state_lfo_time=state_lfo_time+const_lfo_inc
  if state_lfo_time>60 then
    state_lfo_time=0
  end
  -- update level modulated by lfos
  for i=1,6 do
    if (voice[i].lfo==0 or voice[i].level==0) then goto continue end
    softcut.level(i,voice[i].level*math.abs(math.sin(2*math.pi*state_lfo_time/voice[i].lfo+voice[i].lfo_offset)))
    ::continue::
  end
end

function enc(n,d)
  if n==1 then
    if shift==0 then
      -- E1: start loop
      voice[state_v].ls=util.clamp(voice[state_v].ls+d/100,0,voice[state_v].le)
      softcut.loop_start(state_v,1+voice[state_v].ls)
    else
      -- K1+E1: end loop
      voice[state_v].le=util.clamp(voice[state_v].le+d/100,voice[state_v].ls,maxbuffer)
      softcut.loop_end(state_v,1+voice[state_v].le)
    end
  elseif n==2 then
    if shift==0 then
      -- E2: level
      voice[state_v].level=util.clamp(voice[state_v].level+d/100,0,1)
      softcut.level(state_v,voice[state_v].level)
    else
      -- K1+E1: lfo period
      voice[state_v].lfo=util.clamp(voice[state_v].lfo+d/100,0,300)
    end
  elseif n==3 then
    if shift==0 then
      -- E3: pitch
      voice[state_v].rate=voice[state_v].rate+d
      if voice[state_v].rate>11 then
        voice[state_v].rate=11
      elseif voice[state_v].rate<1 then
        voice[state_v].rate=1
      end
      softcut.rate(state_v,rates[voice[state_v].rate])
    else
      -- K1+E3: pan
      voice[state_v].pan=util.clamp(voice[state_v].pan+d/100,-1,1)
      softcut.pan(state_v,voice[state_v].pan)
    end
  end
  redraw()
end

local function update_buffer()
  for i=1,6 do
    softcut.buffer(i,state_buffer)
    softcut.position(i,1)
  end
end

function key(n,z)
  if shift==1 and (n==2 or n==3) and z==1 then
    -- K1+K2: toggle recording into buffer 1
    -- K1+K3: toggle recording into buffer 2
    state_recording=1-state_recording
    state_buffer=n-1
    update_buffer()
    softcut.rec(1,state_recording)
  elseif n==1 and z==1 then
    -- K1: shift toggle
    shift=1-shift
  elseif (n==2 or n==3) and z==1 then
    if shift23==1
      -- K2+K3: toggle buffer that is being played
      state_buffer=3-state_buffer
      update_buffer()
    else
      -- K1 or K2: switch between voices
      state_v=state_v+(n*2-5)
      if state_v>6 then
        state_v=1
      elseif state_v<1 then
        state_v=6
      end
    end
    shift23=1
  elseif (n==2 or n==3) and z==0 then
    shift23=0
  end
  redraw()
end

function redraw()
  screen.clear()
  screen.level(7)
  screen.move(10,10)
  screen.text("hexaphonic v0.1")
  if state_recording==1 then
    screen.move(110,10)
    screen.text("rec")
  end
  screen.move(10,20)
  screen.text("voice "..state_v)
  
  screen.level((1-shift)*6+1)
  screen.move(10,30)
  screen.text(string.format("start: %.2f",voice[state_v].ls))
  screen.level(shift*6+1)
  screen.move(70,30)
  screen.text(string.format("end: %.2f",voice[state_v].le))
  
  screen.level((1-shift)*6+1)
  screen.move(10,40)
  screen.text(string.format("level:  %.2f",voice[state_v].level))
  screen.level(shift*6+1)
  screen.move(70,40)
  screen.text(string.format("lfo: %.2f",voice[state_v].lfo))
  
  screen.level((1-shift)*6+1)
  screen.move(10,50)
  screen.text(string.format("rate:  %.2f",rates[voice[state_v].rate]))
  screen.level(shift*6+1)
  screen.move(70,50)
  screen.text(string.format("pan: %.2f",voice[state_v].pan))
  
  -- screen.move(118,30)
  -- screen.text_right(string.format("%.2f",rate))
  -- screen.move(10,40)
  -- screen.text("rec: ")
  -- screen.move(118,40)
  -- screen.text_right(string.format("%.2f",rec))
  -- screen.move(10,50)
  -- screen.text("pre: ")
  -- screen.move(118,50)
  -- screen.text_right(string.format("%.2f",pre))
  screen.update()
end
