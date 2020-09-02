-- barcode v0.4
-- six-speed six-voice looper
--
-- llllllll.co/t/barcode
--
--
--
--    ▼ instructions below ▼
--
--
-- hold K1 to shift
-- K2 to pauses LFOs
-- K3 starts recording
-- any key stops recording
-- shift+K2 switches buffer
-- shift+K3 clears
-- E1 changes output/rec levels
-- E2 dials through parameters
-- E3 adjusts current parameter

state_recording=0
state_shift=0
state_buffer=1
state_lfo_time=0
state_sticky=0
state_lfo_freeze=0
state_level=1.0
state_parm=0
state_recordingtime=0.0
state_recording_level=1.0
state_buffer_size={60,60} -- seconds in the buffer
state_has_recorded=0
state_message=""
voice={}
rates={0,0.125,0.25,0.5,1,2,4}

const_lfo_inc=0.25 -- seconds between updates
const_line_width=112
const_num_rates=7

function init()
  audio.comp_mix(1) -- turn on compressor
  for i=1,6 do
    voice[i]={}
    voice[i].level={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
    voice[i].pan={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_high_frequency()}
    voice[i].rate={set=0,adj=0,calc=4,lfo=1,lfo_offset=math.random(0,60),lfo_period=0}
    voice[i].sign={set=-1,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
    voice[i].ls={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
    voice[i].le={set=state_buffer_size[state_buffer],adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
  end
  -- initialize voice 1 = standard
  -- intitialize voice 2-6 = decreasing in volume, increasing in pitch
  voice[1].level.set=0.6
  voice[2].level.set=0.6
  voice[3].level.set=1.0
  voice[4].level.set=1.0
  voice[5].level.set=0.1
  voice[6].level.set=0.015
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
    softcut.rate_slew_time(i,1)
    softcut.level_slew_time(i,1)
    softcut.pan_slew_time(i,1)
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
  softcut.rec_level(1,state_recording_level)
  
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
    state_recordingtime=state_recordingtime+const_lfo_inc
    redraw()
    do return end
  end
  
  -- update lfo counter
  if state_lfo_freeze==0 then
    state_lfo_time=state_lfo_time+const_lfo_inc
  end
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
        if voice[i].sign.calc<0.5 then -- 0.5 is to bias towards reverse
          voice[i].sign.calc=-1
        else
          voice[i].sign.calc=1
        end
        softcut.rate(i,voice[i].sign.calc*rates[voice[i].rate.calc])
      elseif j==6 then
        if state_lfo_freeze==0 then
          voice[i].le.lfo=calculate_lfo(voice[i].le.lfo_period,voice[i].le.lfo_offset)*state_buffer_size[state_buffer]/2+2*state_buffer_size[state_buffer]/3
        end
        voice[i].le.calc=util.clamp(voice[i].ls.calc+voice[i].le.lfo+voice[i].le.adj,state_buffer_size[state_buffer]/8,state_buffer_size[state_buffer])
        softcut.loop_end(i,1+voice[i].le.calc)
      elseif j==5 then
        if state_lfo_freeze==0 then
          voice[i].ls.lfo=calculate_lfo(voice[i].ls.lfo_period,voice[i].ls.lfo_offset)*state_buffer_size[state_buffer]/2+state_buffer_size[state_buffer]/3
        end
        voice[i].ls.calc=util.clamp(voice[i].ls.lfo+voice[i].ls.adj,0,2*state_buffer_size[state_buffer]/3)
        softcut.loop_start(i,1+voice[i].ls.calc)
        -- if i==1 then
        --   print(voice[i].le.calc,voice[i].ls.calc)
        -- end
      end
    end
  end
  redraw()
end

function enc(n,d)
  if n==1 then
    if state_recording==1 then
      state_recording_level=util.clamp(state_recording_level+d/100,0,1)
    else
      state_level=util.clamp(state_level+d/100,0,1)
    end
  elseif n==2 then
    -- make knob sticky around levels
    -- if (state_parm-1)%5==0 then
    --   state_sticky=state_sticky+1
    --   if state_sticky>10 then
    --     state_sticky=0
    --   end
    -- end
    if state_sticky==0 then
      state_parm=util.clamp(state_parm+d,0,30)
    end
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
        voice[i].ls.adj=util.clamp(voice[i].ls.adj-d/100,-state_buffer_size[state_buffer],0)
        voice[i].le.adj=util.clamp(voice[i].le.adj+d/100,0,state_buffer_size[state_buffer])
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
    softcut.position(i,1)
  end
  -- reset lfo
  state_lfo_time=0
end

function start_recording()
  state_recording=1
  -- change rate to 1 and slew to 0
  -- to avoid recording slew sound
  softcut.rate_slew_time(1,0)
  softcut.level(1,state_level)
  softcut.rate(1,1)
  softcut.position(1,1)
  softcut.loop_start(1,1)
  softcut.loop_end(1,60)
  softcut.rec_level(1,state_recording_level)
  state_recordingtime=0.0
  softcut.rec(1,1)
  
end

function stop_recording()
  state_recording=0
  state_has_recorded=1
  softcut.rate_slew_time(1,1)
  -- change the buffer size (only if its bigger)
  if state_buffer_size[state_buffer]==60 or state_recordingtime>state_buffer_size[state_buffer] then
    state_buffer_size[state_buffer]=state_recordingtime
  end
  softcut.rec(1,0)
end

function key(n,z)
  if state_recording==1 and z==1 then
    stop_recording()
  elseif n==1 then
    state_shift=z
  elseif state_shift==0 and n==3 and z==1 then
    -- K3: toggle recording into current buffer
    state_recording=1-state_recording
    if state_recording==1 then
      start_recording()
    else
      stop_recording()
    end
  elseif n==2 and state_shift==0 then
    -- K2: toggle freeze lfos
    if z==1 then
      state_lfo_freeze=1-state_lfo_freeze
    end
  elseif n==2 and z==1 and state_shift==1 then
    -- shift+K2: switch buffers
    state_buffer=3-state_buffer
    update_buffer()
    clock.run(function()
      state_message="buffer "..state_buffer
      redraw()
      clock.sleep(1)
      state_message=""
      redraw()
    end)
  elseif state_shift==1 and n==3 and z==1 then
    -- shift+K3: clear current buffer
    state_has_recorded=0
    softcut.buffer_clear_channel(state_buffer)
    clock.run(function()
      state_message="cleared"
      redraw()
      clock.sleep(1)
      state_message=""
      redraw()
    end)
  end
  redraw()
end

local function horziontal_line(value,p)
  if value==0 then
    do return end
  end
  if value<0 then
    screen.move(8+round(const_line_width*(1-math.abs(value))),p)
  end
  screen.line_rel(math.floor(const_line_width*math.abs(value)),0)
end

local function draw_dot(j,p)
  screen.stroke()
  if state_parm==0 then
    screen.level(15)
  elseif j==state_parm then
    screen.level(15)
    screen.move(1,p)
    screen.line_rel(4,0)
    screen.stroke()
  else
    screen.level(1)
  end
end

function redraw()
  screen.clear()
  -- esoteric display
  local p=2
  screen.level(15)
  if state_has_recorded==0 then
    screen.level(1)
  end
  local level_show=state_level
  if state_recording==1 then
    screen.level(15)
    level_show=state_recording_level
  end
  screen.move(8,p)
  horziontal_line(level_show,p)
  screen.move(8,p+1)
  horziontal_line(level_show,p)
  screen.stroke()
  p=p+4+3*state_shift
  j=1+3*state_shift
  for i=1,6 do
    draw_dot(j,p)
    screen.move(8,p)
    horziontal_line(voice[i].level.calc,p)
    p=p+1
    screen.move(8,p)
    horziontal_line(voice[i].level.calc,p)
    p=p+1 j=j+1
    draw_dot(j,p)
    if voice[i].pan.calc<0 then
      screen.move(8+round(const_line_width*0.5*(1-math.abs(voice[i].pan.calc))),p)
      screen.line_rel(round(const_line_width*0.5*math.abs(voice[i].pan.calc)),0)
    else
      screen.move(8+const_line_width*0.5,p)
      screen.line_rel(const_line_width*0.5*math.abs(voice[i].pan.calc),0)
    end
    p=p+1 j=j+1
    draw_dot(j,p) screen.move(8,p)
    horziontal_line(rates[voice[i].rate.calc]/4,p)
    p=p+1 j=j+1
    -- rate sign
    draw_dot(j,p) screen.move(8,p)
    horziontal_line(voice[i].sign.calc*0.5,p)
    p=p+1 j=j+1
    draw_dot(j,p)
    screen.move(8+util.clamp(const_line_width*(voice[i].ls.calc)/state_buffer_size[state_buffer],0,110),p)
    horziontal_line(util.clamp((voice[i].le.calc-voice[i].ls.calc)/state_buffer_size[state_buffer],0,1))
    p=p+4 j=j+1
  end
  screen.stroke()
  
  if state_message~="" then
    show_message(state_message)
  end
  if state_recording==1 then
    show_message(string.format("rec%d %.2fs",state_buffer,state_recordingtime))
  end
  screen.update()
end

--
-- utility functions
--
function show_message(message)
  screen.level(0)
  w=string.len(message)*8
  x=32
  y=24
  screen.move(x,y)
  screen.rect(x,y,w,10)
  screen.fill()
  screen.level(15)
  screen.rect(x,y,w,10)
  screen.stroke()
  screen.move(x+w/2,y+7)
  screen.text_center(message)
end

function round(num)
  if num>=0 then return math.floor(num+.5)
  else return math.ceil(num-.5) end
end

-- define lfos, each returns a period in seconds
function lfo_high_frequency()
  return math.random(1,10)/2 -- 200 mHz to 2 Hz
end

function lfo_med_frequency()
  return math.random(2,30) -- 33 mHz to 500 mHz
end

function lfo_low_frequency()
  return math.random(30,80) -- 12.5 mHz to 33 mHz
end
