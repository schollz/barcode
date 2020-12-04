-- barcode v0.8.0
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

-----------------------

state={
  recording=0,
  shift=0,
  buffer=1,
  lfo_time=0,
  sticky=0,
  lfo_freeze=0,
  level=1.0,
  parm=0,
  recordingtime=0.0,
  buffer_size={60,60},
  has_recorded=0,
  message="",
}
voice={}
rates={0.125,0.25,0.5,1,2,4}

const_lfo_inc=0.25 -- seconds between updates
const_line_width=112
const_num_rates=6

DATA_DIR=_path.data.."barcode/"


function init()
  os.execute("mkdir -p "..DATA_DIR)
  os.execute("mkdir -p "..DATA_DIR.."names/")
  setup_sharing("barcode")
  audio.comp_mix(1) -- turn on compressor

  -- parameters
  params:add_separator("barcode")

  params:add_group("save/load",3)
  params:add_text('save_name',"save as...","")
  params:set_action("save_name",function(y)
    -- prevent banging
    local x=y
    params:set("save_name","")
    if x=="" then 
      do return end 
    end
    -- save
    print(x)
    backup_save(x)
    params:set("save_message","saved as "..x)
  end)
  print("DATA_DIR "..DATA_DIR)
  local name_folder=DATA_DIR.."names/"
  print("name_folder: "..name_folder)
  params:add_file("load_name","load",name_folder)
  params:set_action("load_name",function(y)
    -- prevent banging
    local x=y
    params:set("load_name",name_folder)
    if #x<=#name_folder then 
      do return end 
    end
    -- load
    print("load_name: "..x)
    pathname,filename,ext=string.match(x,"(.-)([^\\/]-%.?([^%.\\/]*))$")
    print("loading "..filename)
    backup_load(filename)
    params:set("save_message","loaded "..filename..".")
  end)
  params:add_text('save_message',">","")

  params:add_option("quantize","lfo bpm sync.",{"off","on"},1)
  params:set_action("quantize",update_parameters)
  params:add_option("recording","recording",{"off","on"},1)
  params:set_action("recording",toggle_recording)
  params:add_control("rate slew time","rate slew time",controlspec.new(0,30,"lin",0.01,1,"s",0.01/30))
  params:set_action("rate slew time",update_parameters)
  params:add_control("pan slew time","pan slew time",controlspec.new(0,30,"lin",0.01,1,"s",0.01/30))
  params:set_action("pan slew time",update_parameters)
  params:add_control("level slew time","level slew time",controlspec.new(0,30,"lin",0.01,1,"s",0.01/30))
  params:set_action("level slew time",update_parameters)
  params:add_taper("pre level","pre level",0,1,1,0)
  params:set_action("pre level",update_parameters)
  params:add_taper("rec level","rec level",0,1,1,0)
  params:set_action("rec level",update_parameters)
  filter_resonance=controlspec.new(0.05,1,'lin',0,0.25,'')
  filter_freq=controlspec.new(20,20000,'exp',0,20000,'Hz')
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

  for i=1,6 do
    voice[i]={}
    voice[i].level={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
    voice[i].pan={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_med_frequency()}
    voice[i].rate={set=0,adj=0,calc=4,lfo=1,lfo_offset=math.random(0,60),lfo_period=0}
    voice[i].sign={set=-1,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
    voice[i].ls={set=0,adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
    voice[i].le={set=state.buffer_size[state.buffer],adj=0,calc=0,lfo=1,lfo_offset=math.random(0,60),lfo_period=lfo_low_frequency()}
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
    softcut.position(i,0)
    softcut.play(i,1)
    softcut.rate_slew_time(i,params:get("rate slew time"))
    softcut.level_slew_time(i,params:get("level slew time"))
    softcut.pan_slew_time(i,params:get("pan slew time"))

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
    return math.sin(2*math.pi*state.lfo_time/period+offset)
  end
end

function update_lfo()
  if state.recording==1 then
    state.recordingtime=state.recordingtime+const_lfo_inc
    redraw()
    do return end
  end

  -- update lfo counter
  if state.lfo_freeze==0 then
    state.lfo_time=state.lfo_time+const_lfo_inc
  end
  if state.lfo_time>60 then
    state.lfo_time=0
  end
  -- update level modulated by lfos
  beat_sec=clock.get_beat_sec()
  for i=1,6 do
    for j=1,6 do
      if j==1 then
        if state.lfo_freeze==0 then
          if params:get("quantize")==1 then
            voice[i].level.lfo=math.abs(calculate_lfo(voice[i].level.lfo_period,voice[i].level.lfo_offset))
          else
            voice[i].level.lfo=math.abs(calculate_lfo(beat_sec*voice[i].level.lfo_period,beat_sec*voice[i].level.lfo_offset))
          end
        end
        voice[i].level.calc=util.clamp(voice[i].level.set*voice[i].level.lfo+voice[i].level.adj,0,1)
        softcut.level(i,state.level*voice[i].level.calc)
      elseif j==2 then
        if state.lfo_freeze==0 then
          if params:get("quantize")==1 then
            voice[i].pan.lfo=calculate_lfo(voice[i].pan.lfo_period,voice[i].pan.lfo_offset)
          else
            voice[i].pan.lfo=calculate_lfo(beat_sec*voice[i].pan.lfo_period,beat_sec*voice[i].pan.lfo_offset)
          end
        end
        voice[i].pan.calc=util.clamp(voice[i].pan.set*voice[i].pan.lfo+voice[i].pan.adj,-1,1)
        softcut.pan(i,voice[i].pan.calc)
      elseif j==3 then
        if state.lfo_freeze==0 then
          if params:get("quantize")==1 then
            voice[i].rate.lfo=math.abs(calculate_lfo(voice[i].rate.lfo_period,voice[i].rate.lfo_offset))
          else
            voice[i].rate.lfo=math.abs(calculate_lfo(beat_sec*voice[i].rate.lfo_period,beat_sec*voice[i].rate.lfo_offset))
          end
        end
        voice[i].rate.calc=util.clamp(round(voice[i].rate.set*voice[i].rate.lfo+voice[i].rate.adj),1,const_num_rates)
      elseif j==4 then
        -- sign lfo oscillates between 0 and 2, since initial sign is -1
        if state.lfo_freeze==0 then
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
        if state.lfo_freeze==0 then
          if params:get("quantize")==1 then
            voice[i].le.lfo=calculate_lfo(voice[i].le.lfo_period,voice[i].le.lfo_offset)*state.buffer_size[state.buffer]/2+2*state.buffer_size[state.buffer]/3
          else
            voice[i].le.lfo=calculate_lfo(beat_sec*voice[i].le.lfo_period,beat_sec*voice[i].le.lfo_offset)*state.buffer_size[state.buffer]/2+2*state.buffer_size[state.buffer]/3
          end
        end
        voice[i].le.calc=util.clamp(voice[i].ls.calc+voice[i].le.lfo+voice[i].le.adj,state.buffer_size[state.buffer]/8,state.buffer_size[state.buffer])
        softcut.loop_end(i,1+voice[i].le.calc)
      elseif j==5 then
        if state.lfo_freeze==0 then
          if params:get("quantize")==1 then
            voice[i].ls.lfo=calculate_lfo(voice[i].ls.lfo_period,voice[i].ls.lfo_offset)*state.buffer_size[state.buffer]/2+state.buffer_size[state.buffer]/3
          else
            voice[i].ls.lfo=calculate_lfo(voice[i].ls.lfo_period*beat_sec,voice[i].ls.lfo_offset*beat_sec)*state.buffer_size[state.buffer]/2+state.buffer_size[state.buffer]/3
          end
        end
        voice[i].ls.calc=util.clamp(voice[i].ls.lfo+voice[i].ls.adj,0,2*state.buffer_size[state.buffer]/3)
        softcut.loop_start(i,voice[i].ls.calc)
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
    if state.recording==1 then
      params:set("rec level",util.clamp(params:get("rec level")+d/100,0,1))
    else
      state.level=util.clamp(state.level+d/100,0,1)
    end
  elseif n==2 then
    -- make knob sticky around levels
    -- if (state.parm-1)%5==0 then
    --   state.sticky=state.sticky+1
    --   if state.sticky>10 then
    --     state.sticky=0
    --   end
    -- end
    if state.sticky==0 then
      state.parm=util.clamp(state.parm+d,0,30)
    end
  elseif n==3 then
    j=1
    for i=1,6 do
      if state.parm==j then
        if state.shift==1 then
          voice[i].level.lfo_period=util.clamp(voice[i].level.lfo_period-d/10,1.0,50)
          print(string.format("voice[i].level.lfo_period %.2f",voice[i].level.lfo_period))
        else
          voice[i].level.adj=util.clamp(voice[i].level.adj+d/100,-2,2)
          print(string.format("level %d %.2f",i,voice[i].level.adj))
        end
        break
      end
      j=j+1
      if state.parm==j then
        if state.shift==1 then
          voice[i].pan.lfo_period=util.clamp(voice[i].pan.lfo_period-d/10,1.0,50)
        else
          voice[i].pan.adj=util.clamp(voice[i].pan.adj+d/100,-2,2)
          print(string.format("pan %d %.2f",i,voice[i].pan.adj))
        end
        break
      end
      j=j+1
      if state.parm==j then
        if state.shift==1 then
          voice[i].rate.lfo_period=util.clamp(voice[i].rate.lfo_period-d/10,1.0,50)
        else
          voice[i].rate.adj=util.clamp(voice[i].rate.adj+d,-const_num_rates,const_num_rates)
          print(string.format("rate %d %.2f",i,voice[i].rate.adj))
        end
        break
      end
      j=j+1
      if state.parm==j then
        if state.shift==1 then
          voice[i].sign.lfo_period=util.clamp(voice[i].sign.lfo_period-d/10,1.0,50)
        else
          voice[i].sign.adj=util.clamp(voice[i].sign.adj+d/100,-2,2)
          print(string.format("sign %d",i))
        end
        break
      end
      j=j+1
      if state.parm==j then
        if state.shift==1 then
          voice[i].ls.lfo_period=util.clamp(voice[i].ls.lfo_period-d/10,1.0,50)
          voice[i].le.lfo_period=util.clamp(voice[i].le.lfo_period-d/10,1.0,50)
        else
          voice[i].ls.adj=util.clamp(voice[i].ls.adj-d/100,-state.buffer_size[state.buffer],0)
          voice[i].le.adj=util.clamp(voice[i].le.adj+d/100,0,state.buffer_size[state.buffer])
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
    softcut.buffer(i,state.buffer)
    softcut.position(i,0)
  end
  -- reset lfo
  state.lfo_time=0
end

function start_recording()
  state.recording=1
  -- change rate to 1 and slew to 0
  -- to avoid recording slew sound
  softcut.rate_slew_time(1,0)
  softcut.level(1,state.level)
  softcut.rate(1,1)
  softcut.position(1,0)
  softcut.loop_start(1,0)
  softcut.loop_end(1,60)
  softcut.rec_level(1,params:get("rec level"))
  softcut.pre_level(1,params:get("pre level"))
  state.recordingtime=0.0
  softcut.rec(1,1)

end

function stop_recording()
  state.recording=0
  state.has_recorded=1
  softcut.rate_slew_time(1,params:get("rate slew time"))
  -- change the buffer size (only if its bigger)
  if state.buffer_size[state.buffer]==60 or state.recordingtime>state.buffer_size[state.buffer] then
    state.buffer_size[state.buffer]=state.recordingtime
  end
  softcut.rec(1,0)
end



function key(n,z)
  if state.recording==1 and z==1 then
    params:set("recording",1)
  elseif n==1 then
    state.shift=z
  elseif state.shift==0 and n==3 and z==1 then
    -- K3: toggle recording into current buffer
    params:set("recording",2)
  elseif n==2 and state.shift==0 then
    -- K2: toggle freeze lfos
    if z==1 then
      state.lfo_freeze=1-state.lfo_freeze
    end
  elseif n==2 and z==1 and state.shift==1 then
    -- shift+K2: switch buffers
    state.buffer=3-state.buffer
    update_buffer()
    clock.run(function()
      state.message="buffer "..state.buffer
      redraw()
      clock.sleep(1)
      state.message=""
      redraw()
    end)
  elseif state.shift==1 and n==3 and z==1 then
    -- shift+K3: clear current buffer
    state.has_recorded=0
    softcut.buffer_clear_channel(state.buffer)
    clock.run(function()
      state.message="cleared"
      redraw()
      clock.sleep(1)
      state.message=""
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
  if state.parm==0 then
    screen.level(15)
  elseif j==state.parm then
    screen.level(15)
    screen.move(1,p)
    if (state.parm-1)%5==0 then
      screen.text("L")
    elseif (state.parm-1)%5==1 then
      screen.text("P")
    elseif (state.parm-1)%5==2 then
      screen.text("R")
    elseif (state.parm-1)%5==3 then
      screen.text("D")
    elseif (state.parm-1)%5==4 then
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
    -- if (state.parm-1)%5==0 then
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
  if state.has_recorded==0 then
    screen.level(1)
  end
  local level_show=state.level
  if state.recording==1 then
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
    screen.move(8+state.shift*3,p)
    horziontal_line(voice[i].level.calc,p)
    p=p+1
    screen.move(8+state.shift*3,p)
    horziontal_line(voice[i].level.calc,p)
    p=p+1 j=j+1
    draw_dot(j,p)
    if voice[i].pan.calc<0 then
      screen.move(8+state.shift*3+round(const_line_width*0.5*(1-math.abs(voice[i].pan.calc))),p)
      screen.line_rel(round(const_line_width*0.5*math.abs(voice[i].pan.calc))-state.shift*3,0)
    else
      screen.move(8+const_line_width*0.5+state.shift*3,p)
      screen.line_rel(const_line_width*0.5*math.abs(voice[i].pan.calc)-state.shift*3,0)
    end
    p=p+1 j=j+1
    draw_dot(j,p)
    screen.move(8+state.shift*3,p)
    horziontal_line(rates[voice[i].rate.calc]/4,p)
    p=p+1 j=j+1
    -- rate sign
    draw_dot(j,p)
    screen.move(8+state.shift*3,p)
    horziontal_line(voice[i].sign.calc*0.5,p)
    p=p+1 j=j+1
    draw_dot(j,p)
    screen.move(8+state.shift*3+util.clamp(const_line_width*(voice[i].ls.calc)/state.buffer_size[state.buffer],0,110),p)
    horziontal_line(util.clamp((voice[i].le.calc-voice[i].ls.calc)/state.buffer_size[state.buffer],0,1))
    p=p+4 j=j+1
  end
  screen.stroke()

  if state.message~="" then
    show_message(state.message)
  end
  if state.recording==1 then
    show_message(string.format("rec%d %.2fs",state.buffer,state.recordingtime))
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
  for i=1,6 do
    softcut.rate_slew_time(i,params:get("rate slew time"))
    softcut.level_slew_time(i,params:get("level slew time"))
    softcut.pan_slew_time(i,params:get("pan slew time"))
  end
  params:write(_path.data..'barcode/'.."barcode.pset")
end


function toggle_recording(x)
  state.recording=x-1
  if state.recording==1 then
    start_recording()
  else
    stop_recording()
  end
end


--
-- saving and loading
--
function backup_save(savename)
  -- create if doesn't exist
  savedir = DATA_DIR..savename.."/"
  os.execute("mkdir -p "..savedir)
  os.execute("echo "..savename.." > "..DATA_DIR.."names/"..savename)

  -- save buffers
  for i=1,2 do
    dur = state.buffer_size[i]
    if dur > 0 and dur < 60 then 
      print(i,dur)
      softcut.buffer_write_mono(savedir..i..".wav",0,dur,i)
    end
  end

  -- save tables
  tab.save(voice,savedir.."voice.txt")
  tab.save(state,savedir.."state.txt")

  -- save the parameter set
  params:write(savedir.."/parameters.pset")
end

function backup_load(savename)
  for i=1,2 do
    if util.file_exists(DATA_DIR..savename.."/"..i..".wav") then 
      softcut.buffer_read_mono(DATA_DIR..savename.."/"..i..".wav",0,0,-1,1,i)
    end
  end

  voice = tab.load(DATA_DIR..savename.."/voice.txt")
  state = tab.load(DATA_DIR..savename.."/state.txt")

  params:read(DATA_DIR..savename.."/parameters.pset")
end


function setup_sharing(script_name)
  if not util.file_exists(_path.code.."norns.online") then
    print("need to donwload norns.online")
    do return end
  end

  local share=include("norns.online/lib/share")

  -- start uploader with name of your script
  local uploader=share:new{script_name=script_name}
  if uploader==nil then
    print("uploader failed, no username?")
    do return end
  end

  -- add parameters
  params:add_group("SHARE",4)

  -- uploader (CHANGE THIS TO FIT WHAT YOU NEED)
  -- select a save
  local names_dir=DATA_DIR.."names/"
  params:add_file("share_upload","upload",names_dir)
  params:set_action("share_upload",function(y)
    -- prevent banging
    local x=y
    params:set("share_download",names_dir) 
    if #x<=#names_dir then 
      do return end 
    end

    -- choose data name
    -- (here dataname is from the selector)
    local dataname=share.trim_prefix(x,DATA_DIR.."names/")
    params:set("share_message","uploading...")
    _menu.redraw()
    print("uploading "..x.." as "..dataname)

    -- upload each buffer
    for i=1,2 do 
      pathtofile = DATA_DIR..dataname.."/"..i..".wav"
      if util.file_exists(pathtofile) then 
        target = DATA_DIR..uploader.upload_username.."-"..dataname.."/"..i..".wav"
        msg = uploader:upload{dataname=dataname,pathtofile=pathtofile,target=target}
        if not string.match(msg,"OK") then 
          params:set("share_message",msg)
          do return end 
        end        
      end
    end

    otherfiles={"parameters.pset","voice.txt","state.txt"}
    for _, f in ipairs(otherfiles) do
      pathtofile = DATA_DIR..dataname.."/"..f
      target =  DATA_DIR..uploader.upload_username.."-"..dataname.."/"..f
      uploader:upload{dataname=dataname,pathtofile=pathtofile,target=target}
    end

    -- upload name file
    pathtofile = DATA_DIR.."names/"..dataname
    target =  DATA_DIR.."names/"..uploader.upload_username.."-"..dataname
    uploader:upload{dataname=dataname,pathtofile=pathtofile,target=target}

    -- goodbye
    params:set("share_message","uploaded.")
  end)

  -- downloader
  download_dir=share.get_virtual_directory(script_name)
  params:add_file("share_download","download",download_dir)
  params:set_action("share_download",function(y)
    -- prevent banging
    local x=y
    params:set("share_download",download_dir) 
    if #x<=#download_dir then 
      do return end 
    end

    -- download
    print("downloading!")
    params:set("share_message","please wait...")
    _menu.redraw()
    local msg=share.download_from_virtual_directory(x)
    params:set("share_message",msg)
  end)
  params:add{type='binary',name='refresh directory',id='share_refresh',behavior='momentary',action=function(v)
    print("updating directory")
    params:set("share_message","refreshing directory.")
    _menu.redraw()
    share.make_virtual_directory()
    params:set("share_message","directory updated.")
  end
  }
params:add_text('share_message',">","")
end


