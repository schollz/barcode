-- barcode v0.7.0
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
-- shift+E3 adjusts freq of lfo

local Formatters=require 'formatters'

state_recording=0
state_shift=0
state_buffer=1
state_lfo_time=0
state_sticky=0
state_lfo_freeze=0
state_level=1.0
state_parm=0
state_recordingtime=0.0
state_buffer_size={60,60} -- seconds in the buffer
state_has_recorded=0
state_message=""
voice={}
rates={0.125,0.25,0.5,1,2,4}

const_lfo_inc=0.25 -- seconds between updates
const_line_width=112
const_num_rates=6

function init()
  audio.comp_mix(1) -- turn on compressor

  -- parameters
  params:add_separator("barcode")
  params:add_option("quantize","lfo bpm sync.",{"off","on"},1)
  params:set_action("quantize",update_parameters)
  params:add_option("recording","recording",{"off","on"},1)
  params:set_action("recording",toggle_recording)
  params:add_taper("pre level","pre level",0,1,1,0)
  params:set_action("pre level",update_parameters)
  params:add_taper("rec level","rec level",0,1,1,0)
  params:set_action("rec level",update_parameters)
  filter_resonance = controlspec.new(0.05,1,'lin',0,0.25,'')
  filter_freq = controlspec.new(20,20000,'exp',0,20000,'Hz')
  params:add {
    type='control',
    id='filter_frequency',
    name='filter cutoff',
    controlspec=filter_freq,
    formatter=Formatters.format_freq,
    action=function(value)
      for i=1,6 do 
        softcut.post_filter_fc(i,value)
      end
    end
  }
  params:add {
    type='control',
    id='filter_reso',
    name='filter resonance',
    controlspec=filter_resonance,
    action=function(value)
      for i=1,6 do 
        softcut.post_filter_rq(i,value)
      end
    end
  }

  params:read(_path.data..'barcode/'.."barcode.pset")

  for i=1,6 do
    voice[i]={}
    voice[i].level={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
    voice[i].pan={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_med_frequency()}
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
  voice[6].level.set=0.05
  voice[1].pan.set=0.4
  voice[2].pan.set=0.5
  voice[3].pan.set=0.6
  voice[4].pan.set=0.7
  voice[5].pan.set=0.8
  voice[6].pan.set=0.8
  voice[1].rate.set=4
  voice[2].rate.set=1
  voice[3].rate.set=2
  voice[4].rate.set=3
  voice[5].rate.set=5
  voice[6].rate.set=6
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

    -- reset filters
    softcut.post_filter_dry(i,0.0)
    softcut.post_filter_lp(i,1.0)
    softcut.post_filter_rq(i,0.3)
    softcut.post_filter_fc(i,44100)

    softcut.pre_filter_dry(i,1.0)
    softcut.pre_filter_lp(i,1.0)
    softcut.pre_filter_rq(i,0.3)
    softcut.pre_filter_fc(i,44100)
  end
  -- set input rec level: input channel, voice, level
  softcut.level_input_cut(1,1,1.0)
  softcut.level_input_cut(2,1,1.0)
  softcut.rec_level(1,params:get("rec level"))
  softcut.pre_level(1,params:get("pre level"))
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
  beat_sec = clock.get_beat_sec()
  for i=1,6 do
    for j=1,6 do
      if j==1 then
        if state_lfo_freeze==0 then
          if params:get("quantize")==1 then 
            voice[i].level.lfo=math.abs(calculate_lfo(voice[i].level.lfo_period,voice[i].level.lfo_offset))
          else
            voice[i].level.lfo=math.abs(calculate_lfo(beat_sec*voice[i].level.lfo_period,beat_sec*voice[i].level.lfo_offset))
          end
        end
        voice[i].level.calc=util.clamp(voice[i].level.set*voice[i].level.lfo+voice[i].level.adj,0,1)
        softcut.level(i,state_level*voice[i].level.calc)
      elseif j==2 then
        if state_lfo_freeze==0 then
          if params:get("quantize")==1 then 
            voice[i].pan.lfo=calculate_lfo(voice[i].pan.lfo_period,voice[i].pan.lfo_offset)
          else
            voice[i].pan.lfo=calculate_lfo(beat_sec*voice[i].pan.lfo_period,beat_sec*voice[i].pan.lfo_offset)
          end
        end
        voice[i].pan.calc=util.clamp(voice[i].pan.set*voice[i].pan.lfo+voice[i].pan.adj,-1,1)
        softcut.pan(i,voice[i].pan.calc)
      elseif j==3 then
        if state_lfo_freeze==0 then
          if params:get("quantize")==1 then 
            voice[i].rate.lfo=math.abs(calculate_lfo(voice[i].rate.lfo_period,voice[i].rate.lfo_offset))
          else
            voice[i].rate.lfo=math.abs(calculate_lfo(beat_sec*voice[i].rate.lfo_period,beat_sec*voice[i].rate.lfo_offset))
          end
        end
        voice[i].rate.calc=util.clamp(round(voice[i].rate.set*voice[i].rate.lfo+voice[i].rate.adj),1,const_num_rates)
      elseif j==4 then
        -- sign lfo oscillates between 0 and 2, since initial sign is -1
        if state_lfo_freeze==0 then
          if params:get("quantize")==1 then 
            voice[i].sign.lfo=1+calculate_lfo(voice[i].sign.lfo_period,voice[i].sign.lfo_offset)
          else
            voice[i].sign.lfo=1+calculate_lfo(beat_sec*voice[i].sign.lfo_period,beat_sec*voice[i].sign.lfo_offset)
          end
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
          if params:get("quantize")==1 then 
            voice[i].le.lfo=calculate_lfo(voice[i].le.lfo_period,voice[i].le.lfo_offset)*state_buffer_size[state_buffer]/2+2*state_buffer_size[state_buffer]/3
          else
            voice[i].le.lfo=calculate_lfo(beat_sec*voice[i].le.lfo_period,beat_sec*voice[i].le.lfo_offset)*state_buffer_size[state_buffer]/2+2*state_buffer_size[state_buffer]/3
          end
        end
        voice[i].le.calc=util.clamp(voice[i].ls.calc+voice[i].le.lfo+voice[i].le.adj,state_buffer_size[state_buffer]/8,state_buffer_size[state_buffer])
        softcut.loop_end(i,1+voice[i].le.calc)
      elseif j==5 then
        if state_lfo_freeze==0 then
          if params:get("quantize")==1 then 
            voice[i].ls.lfo=calculate_lfo(voice[i].ls.lfo_period,voice[i].ls.lfo_offset)*state_buffer_size[state_buffer]/2+state_buffer_size[state_buffer]/3
          else
            voice[i].ls.lfo=calculate_lfo(voice[i].ls.lfo_period*beat_sec,voice[i].ls.lfo_offset*beat_sec)*state_buffer_size[state_buffer]/2+state_buffer_size[state_buffer]/3            
          end
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
      params:set("rec level",util.clamp(params:get("rec level")+d/100,0,1))
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
        if state_shift==1 then
          voice[i].level.lfo_period=util.clamp(voice[i].level.lfo_period-d/10,1.0,50)
          print(string.format("voice[i].level.lfo_period %.2f",voice[i].level.lfo_period))
        else
          voice[i].level.adj=util.clamp(voice[i].level.adj+d/100,-2,2)
          print(string.format("level %d %.2f",i,voice[i].level.adj))
        end
        break
      end
      j=j+1
      if state_parm==j then
        if state_shift==1 then
          voice[i].pan.lfo_period=util.clamp(voice[i].pan.lfo_period-d/10,1.0,50)
        else
          voice[i].pan.adj=util.clamp(voice[i].pan.adj+d/100,-2,2)
          print(string.format("pan %d %.2f",i,voice[i].pan.adj))
        end
        break
      end
      j=j+1
      if state_parm==j then
        if state_shift==1 then
          voice[i].rate.lfo_period=util.clamp(voice[i].rate.lfo_period-d/10,1.0,50)
        else
          voice[i].rate.adj=util.clamp(voice[i].rate.adj+d,-const_num_rates,const_num_rates)
          print(string.format("rate %d %.2f",i,voice[i].rate.adj))
        end
        break
      end
      j=j+1
      if state_parm==j then
        if state_shift==1 then
          voice[i].sign.lfo_period=util.clamp(voice[i].sign.lfo_period-d/10,1.0,50)
        else
          voice[i].sign.adj=util.clamp(voice[i].sign.adj+d/100,-2,2)
          print(string.format("sign %d",i))
        end
        break
      end
      j=j+1
      if state_parm==j then
        if state_shift==1 then
          voice[i].ls.lfo_period=util.clamp(voice[i].ls.lfo_period-d/10,1.0,50)
          voice[i].le.lfo_period=util.clamp(voice[i].le.lfo_period-d/10,1.0,50)
        else
          voice[i].ls.adj=util.clamp(voice[i].ls.adj-d/100,-state_buffer_size[state_buffer],0)
          voice[i].le.adj=util.clamp(voice[i].le.adj+d/100,0,state_buffer_size[state_buffer])
          print(string.format("start/end %d %.2f %.2f",i,voice[i].ls.adj,voice[i].le.adj))
        end
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
  softcut.rec_level(1,params:get("rec level"))
  softcut.pre_level(1,params:get("pre level"))
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
    params:set("recording",1)
  elseif n==1 then
    state_shift=z
  elseif state_shift==0 and n==3 and z==1 then
    -- K3: toggle recording into current buffer
    params:set("recording",2)
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
    if (state_parm-1)%5==0 then
      screen.text("L")
    elseif (state_parm-1)%5==1 then
      screen.text("P")
    elseif (state_parm-1)%5==2 then
      screen.text("R")
    elseif (state_parm-1)%5==3 then
      screen.text("D")
    elseif (state_parm-1)%5==4 then
      screen.text("T")
    end
    -- screen.line_rel(4,0)
    screen.stroke()
    
    -- screen.level(0)
    -- screen.rect(108,1,20,10)
    -- screen.fill()
    -- screen.level(15)
    -- screen.rect(108,1,20,10)
    -- screen.stroke()
    -- screen.move(109,8)
    -- if (state_parm-1)%5==0 then
    --   screen.text(string.format("L %1.2f",voice[1].level.calc))
    -- end
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
    level_show=params:get("rec level")
  end
  screen.move(8,p)
  horziontal_line(level_show,p)
  screen.move(8,p+1)
  horziontal_line(level_show,p)
  screen.stroke()
  p=p+4
  j=1
  for i=1,6 do
    draw_dot(j,p)
    screen.move(8+state_shift*3,p)
    horziontal_line(voice[i].level.calc,p)
    p=p+1
    screen.move(8+state_shift*3,p)
    horziontal_line(voice[i].level.calc,p)
    p=p+1 j=j+1
    draw_dot(j,p)
    if voice[i].pan.calc<0 then
      screen.move(8+state_shift*3+round(const_line_width*0.5*(1-math.abs(voice[i].pan.calc))),p)
      screen.line_rel(round(const_line_width*0.5*math.abs(voice[i].pan.calc))-state_shift*3,0)
    else
      screen.move(8+const_line_width*0.5+state_shift*3,p)
      screen.line_rel(const_line_width*0.5*math.abs(voice[i].pan.calc)-state_shift*3,0)
    end
    p=p+1 j=j+1
    draw_dot(j,p)
    screen.move(8+state_shift*3,p)
    horziontal_line(rates[voice[i].rate.calc]/4,p)
    p=p+1 j=j+1
    -- rate sign
    draw_dot(j,p)
    screen.move(8+state_shift*3,p)
    horziontal_line(voice[i].sign.calc*0.5,p)
    p=p+1 j=j+1
    draw_dot(j,p)
    screen.move(8+state_shift*3+util.clamp(const_line_width*(voice[i].ls.calc)/state_buffer_size[state_buffer],0,110),p)
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
  x=64
  y=28
  w=string.len(message)*6
  screen.rect(x-w/2,y,w,10)
  screen.fill()
  screen.level(15)
  screen.rect(x-w/2,y,w,10)
  screen.stroke()
  screen.move(x,y+7)
  screen.text_center(message)
end

function round(num)
  if num>=0 then return math.floor(num+.5)
  else return math.ceil(num-.5) end
end

-- define lfos, each returns a period in seconds
function lfo_high_frequency()
  return math.random(2,10)
end

function lfo_med_frequency()
  return math.random(10,20)
end

function lfo_low_frequency()
  return math.random(20,40)
end

function update_parameters(x)
  params:write(_path.data..'barcode/'.."barcode.pset")
end


function toggle_recording(x)
  state_recording=x-1
  if state_recording==1 then
    start_recording()
  else
    stop_recording()
  end
end
