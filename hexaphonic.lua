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
const_line_width=116
maxbuffer=15
range_level={0,1}
range_pan={-1,1}
range_rate={1,11}
range_ls={0,15}
range_le={0,15}

function init()
  for i=1,6 do
    voice[i]={level=0,level2=0,pan=0,pan2=0,rate=9,rate2=9,ls=math.random(0,6),ls2=0,le=math.random(6,15),le2=3,buffer=1,rate_sign=1}
    voice[i].lfo_offset={math.random(0,60),math.random(0,60),math.random(0,60),math.random(0,60),math.random(0,60),math.random(0,60)}
    voice[i].lfo_period={math.random(20,40),math.random(2,20),0,math.random(80,120),math.random(80,120),math.random(80,120)}
    voice[i].lfo={1,1,1,1,1,1}
  end
  voice[1].level=0.5
  voice[2].level=0.5
  voice[3].level=0.3
  voice[4].level=0.3
  voice[5].level=0.4
  voice[6].level=0.1
  voice[1].pan=0.2
  voice[2].pan=-0.2
  voice[3].pan=0.4
  voice[4].pan=-0.4
  voice[5].pan=0.6
  voice[6].pan=-0.6
  voice[1].rate=3
  voice[2].rate=3
  voice[3].rate=4
  voice[4].rate=4
  voice[5].rate=5
  voice[6].rate=2
  
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
  if state_recording==1 then
    do return end
  end
  
  -- update lfo counter
  state_lfo_time=state_lfo_time+const_lfo_inc
  if state_lfo_time>60 then
    state_lfo_time=0
  end
  -- update level modulated by lfos
  for i=1,6 do
    local loop_end=15
    for j=1,6 do
      if voice[i].lfo_period[j]==0 then
        voice[i].lfo[j]=1
      else
        voice[i].lfo[j]=math.sin(2*math.pi*state_lfo_time/voice[i].lfo_period[j]+voice[i].lfo_offset[j])
      end
      if j==1 then
        voice[i].level2=voice[i].level*math.abs(voice[i].lfo[j])
        softcut.level(i,voice[i].level2)
      elseif j==2 then
        voice[i].pan2=voice[i].pan*voice[i].lfo[j]
        softcut.pan(i,voice[i].pan2)
      elseif j==3 then
        voice[i].rate2=math.floor(util.clamp(voice[i].rate*math.abs(voice[i].lfo[j]),1,11))
      elseif j==4 then
        voice[i].le2=util.clamp(voice[i].le*math.abs(voice[i].lfo[j]),8,15)
        softcut.loop_end(i,1+voice[i].le2)
      elseif j==5 then
        voice[i].ls2=util.clamp(voice[i].ls*math.abs(voice[i].lfo[j]),0,voice[i].le2)
        softcut.loop_start(i,1+voice[i].ls2)
      elseif j==6 then
        voice[i].rate_sign=round(voice[i].lfo[j])
        softcut.rate(i,rates[voice[i].rate2]*voice[i].rate_sign)
      end
    end
  end
  redraw()
end

function round(num)
  if num>=0 then return math.floor(num+.5)
  else return math.ceil(num-.5) end
end
-- function enc(n,d)
--   if n==1 then
--     if shift==0 then
--       -- E1: start loop
--       voice[state_v].ls=util.clamp(voice[state_v].ls+d/100,0,voice[state_v].le)
--       softcut.loop_start(state_v,1+voice[state_v].ls)
--     else
--       -- K1+E1: end loop
--       voice[state_v].le=util.clamp(voice[state_v].le+d/100,voice[state_v].ls,maxbuffer)
--       softcut.loop_end(state_v,1+voice[state_v].le)
--     end
--   elseif n==2 then
--     if shift==0 then
--       -- E2: level
--       voice[state_v].level=util.clamp(voice[state_v].level+d/100,0,1)
--     else
--       -- K1+E1: lfo period
--       -- voice[state_v].lfo=util.clamp(voice[state_v].lfo+d/100,0,300)
--     end
--   elseif n==3 then
--     if shift==0 then
--       -- E3: pitch
--       voice[state_v].rate=voice[state_v].rate+d
--       if voice[state_v].rate>11 then
--         voice[state_v].rate=11
--       elseif voice[state_v].rate<1 then
--         voice[state_v].rate=1
--       end
--       softcut.rate(state_v,rates[voice[state_v].rate])
--     else
--       -- K1+E3: pan
--       voice[state_v].pan=util.clamp(voice[state_v].pan+d/100,-1,1)
--     end
--   end
--   redraw()
-- end

local function update_buffer()
  for i=1,6 do
    softcut.buffer(i,state_buffer)
    -- softcut.position(i,1)
  end
  -- reset lfo
  state_lfo_time=0
end

function key(n,z)
  if shift==1 and (n==2 or n==3) and z==1 then
    -- K1+K2: toggle recording into buffer 1
    -- K1+K3: toggle recording into buffer 2
    state_buffer=n-1
    update_buffer()
    state_recording=1-state_recording
    if state_recording==1 then
      -- turn off all voices, except first
      -- change rate to 1
      for i=2,6 do
        softcut.level(i,0)
      end
      softcut.rate(1,1)
      softcut.position(1,1)
    end
    softcut.rec(1,state_recording)
  elseif n==1 and z==1 then
    -- K1: shift toggle
    shift=1-shift
  elseif (n==2 or n==3) and z==1 then
    if shift23==1 then
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

local function horziontal_line(value,p)
  screen.level(7)
  if value<0 then
    screen.move(const_line_width*(1-math.abs(value)),p)
  else
    screen.level(7)
  end
  screen.line_rel(const_line_width*math.abs(value),0)
end

function redraw()
  screen.clear()
  -- esoteric display
  screen.level(7)
  screen.move(1,10)
  screen.text("hexaphonic v0.1")
  if state_recording==1 then
    screen.move(const_line_width,10)
    screen.text(string.format("rec %d",state_buffer))
  end
  local p=10
  for i=1,6 do
    p=p+4
    screen.move(8,p)
    horziontal_line(voice[i].level2,p)
    p=p+1
    screen.move(8,p)
    horziontal_line(voice[i].pan2,p)
    p=p+1
    screen.move(8,p)
    horziontal_line(rates[voice[i].rate2]/4,p)
    p=p+1
    -- rate sign
    screen.move(8,p)
    horziontal_line((voice[i].lfo[6]+1)/2,p)
    p=p+1
    screen.level(7)
    screen.move(8+util.clamp(const_line_width*(voice[i].ls2)/15,0,110),p)
    horziontal_line(util.clamp((voice[i].le2-voice[i].ls2)/15,0,1))
    p=p+1
  end
  screen.stroke()
  -- normal display
  -- screen.level(7)
  -- screen.move(10,10)
  -- screen.text("hexaphonic v0.1")
  -- if state_recording==1 then
  --   screen.move(const_line_width,10)
  --   screen.text("rec")
  -- end
  -- screen.move(10,20)
  -- screen.text("voice "..state_v)
  
  -- screen.level((1-shift)*6+1)
  -- screen.move(10,30)
  -- screen.text(string.format("start: %.2f",voice[state_v].ls))
  -- screen.level(shift*6+1)
  -- screen.move(70,30)
  -- screen.text(string.format("end: %.2f",voice[state_v].le))
  
  -- screen.level((1-shift)*6+1)
  -- screen.move(10,40)
  -- screen.text(string.format("level:  %.2f",voice[state_v].level))
  -- screen.level(shift*6+1)
  -- screen.move(70,40)
  -- screen.text(string.format("lfo: %.2f",voice[state_v].lfo))
  
  -- screen.level((1-shift)*6+1)
  -- screen.move(10,50)
  -- screen.text(string.format("rate:  %.2f",rates[voice[state_v].rate]))
  -- screen.level(shift*6+1)
  -- screen.move(70,50)
  -- screen.text(string.format("pan: %.2f",voice[state_v].pan))
  
  screen.update()
end

