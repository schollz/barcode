-- barcode v0.1
-- 6 voice looper
--
-- press K2/K3 to record
-- press again to play
-- E1 changes total levels
-- E2 dials through parameters
-- E3 adjusts current parameter
-- K1+K2 freezes current lfos

state_recording=0
state_v=1
state_shift=0
state_buffer=1
state_lfo_time=0
state_lfo_freeze=0
state_level=1.0
state_parm=0
voice={}
rates={0,0.125,0.25,0.5,1,2,4}

const_lfo_inc=0.25
const_line_width=116
const_num_rates=7
const_buffer_size=8

function init()
  audio.comp_mix(1)
  for i=1,6 do
    voice[i]={}
    voice[i].level={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=math.random(30,60)}
    voice[i].pan={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=math.random(30,60)}
    voice[i].rate={set=0,adj=0,calc=4,lfo=1,lfo_offset=math.random(0,60),lfo_period=0}
    voice[i].sign={set=-1,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=math.random(30,60)}
    voice[i].ls={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=math.random(30,60)}
    voice[i].le={set=const_buffer_size,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=math.random(30,60)}
  end
  voice[1].level.set=1.0
  voice[2].level.set=0.8
  voice[3].level.set=0.6
  voice[4].level.set=0.3
  voice[5].level.set=0.2
  voice[6].level.set=0.05
  voice[1].pan.set=0.3
  voice[2].pan.set=0.4
  voice[3].pan.set=0.5
  voice[4].pan.set=0.6
  voice[5].pan.set=0.7
  voice[6].pan.set=0.8
  voice[1].rate.set=5
  voice[2].rate.set=2
  voice[3].rate.set=3
  voice[4].rate.set=4
  voice[5].rate.set=6
  voice[6].rate.set=7
  for i=1,6 do
    voice[i].level.calc=voice[i].level.set
    voice[i].pan.calc=voice[i].pan.set
    voice[i].rate.calc=voice[i].rate.set
  end
  
  -- send audio input to softcut input
  audio.level_adc_cut(1)
  softcut.buffer_clear()
  for i=1,6 do
    softcut.enable(i,1)
    softcut.buffer(i,1)
    softcut.loop(i,1)
    softcut.position(i,1)
    softcut.play(i,1)
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

function calculate_lfo(period,offset)
  if period==0 then
    return 1
  else
    return math.sin(2*math.pi*state_lfo_time/period+offset)
  end
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
    for j=1,6 do
      if j==1 then
        if state_lfo_freeze==0 then
          voice[i].level.lfo=math.abs(calculate_lfo(voice[i].level.lfo_period,voice[i].level.lfo_offset))
        end
        voice[i].level.calc=util.clamp(voice[i].level.set*voice[i].level.lfo+voice[i].level.adj,0,1)
        softcut.level(i,state_level*voice[i].level.calc)
      elseif j==2 then
        if state_lfo_freeze==0 then
          voice[i].pan.lfo=calculate_lfo(voice[i].pan.lfo_period,voice[i].pan.lfo_offset)
        end
        voice[i].pan.calc=util.clamp(voice[i].pan.set*voice[i].pan.lfo+voice[i].pan.adj,-1,1)
        softcut.pan(i,voice[i].pan.calc)
      elseif j==3 then
        if state_lfo_freeze==0 then
          voice[i].rate.lfo=math.abs(calculate_lfo(voice[i].rate.lfo_period,voice[i].rate.lfo_offset))
        end
        voice[i].rate.calc=util.clamp(round(voice[i].rate.set*voice[i].rate.lfo+voice[i].rate.adj),1,const_num_rates)
      elseif j==4 then
        -- sign lfo oscillates between 0 and 2, since initial sign is -1
        if state_lfo_freeze==0 then
          voice[i].sign.lfo=1+calculate_lfo(voice[i].sign.lfo_period,voice[i].sign.lfo_offset)
        end
        voice[i].sign.calc=util.clamp(voice[i].sign.set+voice[i].sign.lfo+voice[i].sign.adj,-1,1)
        if voice[i].sign.calc<0 then
          voice[i].sign.calc=-1
        else
          voice[i].sign.calc=1
        end
        softcut.rate(i,voice[i].sign.calc*rates[voice[i].rate.calc])
      elseif j==5 then
        if state_lfo_freeze==0 then
          voice[i].le.lfo=calculate_lfo(voice[i].le.lfo_period,voice[i].le.lfo_offset)*const_buffer_size/2+const_buffer_size/2
        end
        voice[i].le.calc=util.clamp(voice[i].le.lfo+voice[i].le.adj,1,const_buffer_size)
        softcut.loop_end(i,1+voice[i].le.calc)
      elseif j==6 then
        if state_lfo_freeze==0 then
          voice[i].ls.lfo=calculate_lfo(voice[i].ls.lfo_period,voice[i].ls.lfo_offset)*const_buffer_size/2+const_buffer_size/2
        end
        voice[i].ls.calc=util.clamp(voice[i].ls.lfo+voice[i].ls.adj,0,voice[i].le.calc-2)
        softcut.loop_start(i,1+voice[i].ls.calc)
        if i==1 then
          print(voice[i].le.calc,voice[i].ls.calc)
        end
      end
    end
  end
  redraw()
end

function round(num)
  if num>=0 then return math.floor(num+.5)
  else return math.ceil(num-.5) end
end

function enc(n,d)
  if n==1 then
    state_level=util.clamp(state_level+d/100,0,1)
  elseif n==2 then
    state_parm=util.clamp(state_parm+d,0,30)
  elseif n==3 then
    j=1
    for i=1,6 do
      if state_parm==j then
        voice[i].level.adj=util.clamp(voice[i].level.adj+d/100,-2,2)
        print(string.format("level %d %.2f",i,voice[i].level.adj))
        break
      end
      j=j+1
      if state_parm==j then
        voice[i].pan.adj=util.clamp(voice[i].pan.adj+d/100,-2,2)
        print(string.format("pan %d %.2f",i,voice[i].pan.adj))
        break
      end
      j=j+1
      if state_parm==j then
        voice[i].rate.adj=util.clamp(voice[i].rate.adj+d,-const_num_rates,const_num_rates)
        print(string.format("rate %d %.2f",i,voice[i].rate.adj))
        break
      end
      j=j+1
      if state_parm==j then
        voice[i].sign.adj=util.clamp(voice[i].sign.adj+d/100,-2,2)
        print(string.format("sign %d",i))
        break
      end
      j=j+1
      if state_parm==j then
        voice[i].ls.adj=util.clamp(voice[i].ls.adj-d/100,-const_buffer_size,0)
        voice[i].le.adj=util.clamp(voice[i].le.adj+d/100,0,const_buffer_size)
        print(string.format("start/end %d %.2f %.2f",i,voice[i].ls.adj,voice[i].le.adj))
        break
      end
      j=j+1
    end
  end
end

local function update_buffer()
  for i=1,6 do
    softcut.buffer(i,state_buffer)
    -- softcut.position(i,1)
  end
  -- reset lfo
  state_lfo_time=0
end

function key(n,z)
  if n==1 then
    state_shift=z
  elseif n==2 and state_shift==1 then
    -- K1+K2: toggle freeze lfos
    state_lfo_freeze=1-state_lfo_freeze
  elseif (n==2 or n==3) and z==1 then
    -- K2: toggle recording into buffer 1
    -- K3: toggle recording into buffer 2
    state_buffer=n-1
    update_buffer()
    state_recording=1-state_recording
    if state_recording==1 then
      -- turn off all voices, except first
      -- change rate to 1
      for i=2,6 do
        softcut.level(i,0)
      end
      softcut.level(1,1)
      softcut.rate(1,1)
      softcut.position(1,1)
      softcut.loop_start(1,1)
      softcut.loop_end(1,const_buffer_size+1)
    end
    softcut.rec(1,state_recording)
  end
  redraw()
end

local function horziontal_line(value,p)
  if value<0 then
    screen.move(8+round(const_line_width*(1-math.abs(value))),p)
  end
  screen.line_rel(round(const_line_width*math.abs(value)),0)
end

local function draw_dot(j,p)
  if j==state_parm then
    screen.move(1,p)
    screen.line_rel(4,0)
  end
end

function redraw()
  screen.clear()
  -- esoteric display
  screen.move(1,10)
  if state_shift==1 then
    screen.move(2,11)
  end
  local freezestring=">"
  if state_lfo_freeze==1 then
    freezestring="-"
  end
  screen.text("barcode v0.1 "..freezestring)
  if state_recording==1 then
    screen.move(105,10)
    screen.text(string.format("rec %d",state_buffer))
  end
  local p=14
  screen.move(8,p)
  horziontal_line(state_level,p)
  p=p+3
  j=1
  for i=1,6 do
    draw_dot(j,p) screen.move(8,p)
    horziontal_line(voice[i].level.calc,p)
    p=p+1 j=j+1
    draw_dot(j,p) screen.move(8,p)
    horziontal_line(voice[i].pan.calc,p)
    p=p+1 j=j+1
    draw_dot(j,p) screen.move(8,p)
    horziontal_line(rates[voice[i].rate.calc]/4,p)
    p=p+1 j=j+1
    -- rate sign
    draw_dot(j,p) screen.move(8,p)
    horziontal_line(voice[i].sign.calc*0.5,p)
    p=p+1 j=j+1
    draw_dot(j,p)
    screen.move(8+util.clamp(const_line_width*(voice[i].ls.calc)/const_buffer_size,0,110),p)
    horziontal_line(util.clamp((voice[i].le.calc-voice[i].ls.calc)/const_buffer_size,0,1))
    p=p+3 j=j+1
  end
  screen.stroke()
  screen.update()
end

