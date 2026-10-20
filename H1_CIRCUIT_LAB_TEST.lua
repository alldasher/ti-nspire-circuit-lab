on={}
dofile("H1_CIRCUIT_LAB.lua")
local L=LabCore
local function near(x,y,tol,name)
  assert(type(x)=="number",name.." is not numeric")
  assert(math.abs(x-y)<tol,name.." got "..x.." expected "..y)
end
local function node(x,y) return L.node(x,y) end
local function av(c,r)
  local ia=r.net.idx(c.pin);local oa=r.net.idx(c.pout)
  local a,b=r.ac.re[ia],r.ac.im[ia]
  local d,e=r.ac.re[oa],r.ac.im[oa]
  return (d*a+e*b)/(a*a+b*b),(e*a-d*b)/(a*a+b*b)
end
local function mustSolve(c)
  local r,e=L.solve(c)
  assert(r,e or "solve failed")
  return r
end
assert(L.parse("2.2k")==2200)
near(L.parse("10m"),0.01,1e-12,"parse milli")
near(L.parse("1@E-3"),0.001,1e-12,"parse exponent")
assert(L.parse("abc")==nil)
local div=L.demoDivider();local d=mustSolve(div)
near(d.dc[d.net.idx(node(1,1))],5,1e-5,"divider DC")
local dr,di=av(div,d);near(dr,0.5,1e-7,"divider AC")
near(di,0,1e-7,"divider phase")
local ground=node(0,2)
local dcVoltage=L.measureVoltage(d,node(1,1),ground,"DC")
near(dcVoltage.value,5,1e-6,"two-node DC voltage")
near(L.measureVoltage(d,ground,node(1,1),"DC").value,-5,1e-6,"voltage polarity reversal")
local acVoltage=L.measureVoltage(d,node(1,1),ground,"AC")
near(acVoltage.peak,0.5,1e-7,"two-node AC peak voltage")
near(acVoltage.rms,0.5/math.sqrt(2),1e-7,"two-node AC RMS voltage")
assert(L.measureVoltage(d,node(7,4),ground,"DC")==nil,"unconnected voltage node rejected")
local divR1,divV1
for _,p in ipairs(div.parts) do
  if p.name=="R1" then divR1=p elseif p.name=="V1" then divV1=p end
end
near(L.measureCurrent(div,d,divR1,"DC").value,0.005,1e-8,"resistor DC current")
near(L.measureCurrent(div,d,divR1,"AC").peak,0.0005,1e-8,"resistor AC current")
near(L.measureCurrent(div,d,divV1,"DC").value,-0.005,1e-8,"source current sign")

-- A resistor can be put in any free branch, including a center branch.
local middle=L.new()
assert(L.place(middle,"R",node(3,2),1))
assert(L.place(middle,"R",node(4,2),2))
assert(not L.place(middle,"R",node(3,2),1),"overlap must be rejected")

local ce=L.demoCE();local cr=mustSolve(ce)
local ar,ai=av(ce,cr)
assert(ar<0 and math.abs(ai)<0.01,"CE must invert at midband")
near(ar,-2.1286,0.02,"CE lecture-method cross-check")
assert(cr.dc[cr.net.idx(node(4,1))]>cr.dc[cr.net.idx(node(4,3))],"CE active VCE")
for _,p in ipairs(ce.parts) do if p.kind=="Q" then
  local dcI=L.measureCurrent(ce,cr,p,"DC")
  local acI=L.measureCurrent(ce,cr,p,"AC")
  assert(dcI.value>0 and dcI.base>0 and acI.peak>=0 and acI.basePeak>=0,"BJT collector/base measurements")
end end
local satCE=L.demoCE()
for _,p in ipairs(satCE.parts) do if p.name=="R1" then p.value=100000 end end
local sr=mustSolve(satCE);local warned=false
for _,line in ipairs(sr.lines) do if line.kind=="warn" then warned=true end end
assert(warned,"saturated BJT must warn about lecture gain formula")

-- 1 kOhm / 1 uF RC low-pass at its corner frequency.
local rc=L.new();rc.freq=1/(2*math.pi*1000*1e-6)
local v=L.place(rc,"V",node(0,1),2);v.value=0;v.ac=1
L.place(rc,"G",node(0,2),1)
local rr=L.place(rc,"R",node(0,1),1);rr.value=1000
local cap=L.place(rc,"C",node(1,1),2);cap.value=1e-6
L.place(rc,"W",node(1,2),3)
rc.pin=node(0,1);rc.pout=node(1,1)
local rcr=mustSolve(rc)
local rr1,ri1=av(rc,rcr)
near(rr1,0.5,0.001,"RC real gain")
near(ri1,-0.5,0.001,"RC imag gain")
local rcVoltage=L.measureVoltage(rcr,node(1,1),node(0,2),"AC")
near(rcVoltage.angle,-45,0.2,"RC output phase")
near(L.measureCurrent(rc,rcr,cap,"DC").value,0,1e-12,"capacitor DC open current")
near(L.measureCurrent(rc,rcr,cap,"AC").peak,1/(math.sqrt(2)*1000),1e-5,"capacitor AC current")

local dtest=L.new()
local dv=L.place(dtest,"V",node(0,1),2);dv.value=1;dv.ac=0.01
L.place(dtest,"G",node(0,2),1)
local dl=L.place(dtest,"R",node(0,1),1);dl.value=1000
L.place(dtest,"D",node(1,1),2)
L.place(dtest,"W",node(1,2),3)
local diodeResult=mustSolve(dtest)
local diodeV=diodeResult.dc[diodeResult.net.idx(node(1,1))]
assert(diodeV>0.4 and diodeV<0.8,"forward diode DC bias")

local mos=L.new()
local mv=L.place(mos,"V",node(6,0),2);mv.value=12
L.place(mos,"G",node(6,1),1)
L.place(mos,"W",node(5,0),1);L.place(mos,"W",node(4,0),1)
local md=L.place(mos,"R",node(4,0),2);md.value=2200
L.place(mos,"M",node(4,2),1)
local ms=L.place(mos,"R",node(4,3),2);ms.value=1000
L.place(mos,"G",node(4,4),1)
local mg=L.place(mos,"V",node(3,2),2);mg.value=6;mg.ac=0.01
L.place(mos,"G",node(3,3),1)
mos.pin=node(3,2);mos.pout=node(4,1)
local mr=mustSolve(mos)
local mar=av(mos,mr)
assert(mar<0,"NMOS common source gain should invert")

local jf=L.new()
local jv=L.place(jf,"V",node(6,0),2);jv.value=15
L.place(jf,"G",node(6,1),1)
L.place(jf,"W",node(5,0),1);L.place(jf,"W",node(4,0),1)
local jd=L.place(jf,"R",node(4,0),2);jd.value=1000
L.place(jf,"J",node(4,2),1)
local js=L.place(jf,"R",node(4,3),2);js.value=220
L.place(jf,"G",node(4,4),1)
L.place(jf,"G",node(3,2),1)
local jr=mustSolve(jf)
assert(jr.dc[jr.net.idx(node(4,3))]>0,"JFET source bias")

-- Unbiased JFET / NMOS parts should not crash the solver.
local q=L.new();local qp=L.place(q,"Q",node(4,2),1)
assert(qp and qp.a==node(3,2) and qp.b==node(4,1) and qp.c==node(4,3))
assert(not L.place(q,"R",node(5,2),3),"center of transistor is blocked")
local orientations={
  {node(3,2),node(4,1),node(4,3)},
  {node(4,1),node(5,2),node(3,2)},
  {node(5,2),node(4,3),node(4,1)},
  {node(4,3),node(3,2),node(5,2)}
}
for _,kind in ipairs({"Q","M","J"}) do
  for dir=1,4 do
    local c=L.new();local p=L.place(c,kind,node(4,2),dir)
    assert(p and p.dir==dir,"3-pin placement direction")
    for k,key in ipairs({"a","b","c"}) do assert(p[key]==orientations[dir][k],kind.." terminal "..key.." direction "..dir) end
    assert(L.rotate(c,p))
    local nextDir=dir%4+1
    assert(p.dir==nextDir and p.a==orientations[nextDir][1])
  end
end
assert(not L.place(L.new(),"Q",node(0,2),2),"rotated part must fit grid")
local blocked=L.new();local bq=L.place(blocked,"Q",node(4,2),1)
assert(L.place(blocked,"Q",node(5,2),3),"second transistor beside first")
assert(not L.rotate(blocked,bq),"rotation must reject another transistor center")
assert(bq.dir==1 and bq.a==node(3,2),"failed rotation leaves circuit unchanged")
local floating=L.new();L.place(floating,"R",node(2,2),1)
assert(L.solve(floating)==nil,"ground check")

-- Handheld UI: exact home rows, keypad navigation, native editor, drawing.
local widget
D2Editor={newRichText=function()
  local e={value="",visible=false,focused=false}
  function e:move(x,y) self.x=x;self.y=y;return self end
  function e:resize(w,h) self.w=w;self.h=h;return self end
  for _,name in ipairs({"setBorder","setFontSize"}) do e[name]=function(self) return self end end
  function e:setVisible(v) self.visible=v;return self end
  function e:setText(v) self.value=v;return self end
  function e:getText() return self.value end
  function e:setFocus(v) self.focused=v;return self end
  function e:registerFilter(v) self.filter=v;return self end
  widget=e;return e
end}
local screenW,screenH=320,210
platform={window={width=function() return screenW end,height=function() return screenH end,invalidate=function() end}}
local labels={};local rects={};local gc={}
gc.getStringWidth=function(_,s) return #s*5 end
for _,name in ipairs({"setColorRGB","setFont","drawLine","drawArc","fillArc"}) do
  gc[name]=function() end
end
for _,name in ipairs({"fillRect","drawRect"}) do
  gc[name]=function(_,x,y,w,h) rects[#rects+1]={x=x,y=y,w=w,h=h} end
end
local positions={}
gc.drawString=function(_,s,x,y,alignment)
  assert(alignment=="top","explicit top-aligned text required on handheld")
  labels[#labels+1]=s;positions[#positions+1]={x=x,y=y,text=s}
end
local function painted(s)
  labels={};positions={};rects={};on.paint(gc)
  for _,item in ipairs(positions) do
    assert(item.y>=0 and item.y<screenH,"text clipped vertically: "..item.text.." at "..item.y.." / "..screenH)
    assert(item.x>=0 and item.x+gc:getStringWidth(item.text)<=screenW+2,
      "text clipped horizontally: "..item.text.." at "..item.x.." / "..screenW)
  end
  for _,r in ipairs(rects) do
    assert(r.x>=0 and r.y>=0 and r.x+r.w<=screenW+1 and r.y+r.h<=screenH+1,
      "rectangle clipped at "..r.x..","..r.y.." size "..r.w.."x"..r.h)
  end
  for _,v in ipairs(labels) do if v==s then return true end end
  return false
end
on.construction()
assert(painted("H1 CIRCUIT LAB"))
on.charIn("2");assert(painted("CHOOSE MEASUREMENT"))
on.escapeKey();assert(painted("H1 CIRCUIT LAB"),"measurement menu returns home when opened there")
on.mouseDown(95,120) -- fourth row: divider demo, precise row hitbox
assert(painted("CIRCUIT LAB"))
local saved=on.save();assert(#saved.circuit.parts==4)
on.arrowLeft();on.arrowDown() -- cursor (1,3), no part
on.arrowUp();on.arrowUp() -- cursor (1,1), R2 anchor
on.enterKey();assert(painted("PART SETTINGS"))
on.enterKey();assert(painted("ENTER VALUE"))
widget.value="2k";widget.filter.enterKey()
assert(not widget.visible and not widget.focused,"editor closes")
assert(painted("PART SETTINGS"))
local changed=false
for _,p in ipairs(on.save().circuit.parts) do if p.kind=="R" and p.anchor==node(1,1) then near(p.value,2000,1e-8,"edited R2");changed=true end end
assert(changed)
on.escapeKey();on.charIn("9")
for _,p in ipairs(on.save().circuit.parts) do if p.kind=="R" and p.anchor==node(1,1) then near(p.value,1000,1e-8,"undo property") end end
on.charIn("8");assert(painted("COMPONENTS"))
on.arrowDown();on.enterKey();assert(painted("CIRCUIT LAB"))
on.restore(saved);assert(painted("CIRCUIT LAB"))
on.mouseDown(40,79) -- exact resistor midpoint hit target
assert(painted("PART SETTINGS"))
assert(painted("R1  R"),"midpoint must select R1")
on.escapeKey()
on.charIn("4");assert(painted("ANALYSIS"))
on.escapeKey();assert(painted("CIRCUIT LAB"))
-- Handheld Del is delivered as backspaceKey, and must remove the part.
on.restore(saved)
on.mouseDown(40,79);assert(painted("PART SETTINGS"))
on.backspaceKey();assert(painted("CIRCUIT LAB"))
assert(#on.save().circuit.parts==3,"handheld Del removed selected resistor")
on.charIn("9");assert(#on.save().circuit.parts==4,"undo Del")
local oneQ=L.new();local onePart=L.place(oneQ,"Q",node(4,2),1)
on.restore({circuit=oneQ,cx=4,cy=2,tool=1,dir=1})
on.charIn("5");assert(painted("PART SETTINGS"))
on.charIn("3");assert(onePart.dir==2 and onePart.a==node(4,1),"settings 3 rotates existing BJT")
painted("PART SETTINGS")
local guide=false
for _,s in ipairs(labels) do if s:find("B:U C:R E:L",1,true) then guide=true end end
assert(guide,"settings explains rotated transistor terminals")
on.escapeKey();on.charIn("9")
assert(on.save().circuit.parts[1].dir==1,"undo transistor rotation")

-- End-to-end keypad measurement flow: mode, two voltage nodes, part current.
on.restore({circuit=L.demoDivider(),cx=1,cy=1,tool=1,dir=1})
on.charIn("0");assert(painted("CHOOSE MEASUREMENT"))
on.charIn("1");assert(painted("PICK TWO NODES"))
on.enterKey();on.arrowLeft();on.arrowDown();on.enterKey()
assert(painted("MEASUREMENT"))
assert(painted("DC VOLTAGE"))
on.charIn("0");assert(painted("CHOOSE MEASUREMENT"))
on.charIn("2");assert(painted("PICK TWO NODES"))
on.enterKey();on.arrowRight();on.arrowUp();on.enterKey()
assert(painted("MEASUREMENT"))
assert(painted("AC VOLTAGE"))
local rmsShown=false
for _,s in ipairs(labels) do if s:find("RMS = ",1,true) then rmsShown=true end end
assert(rmsShown,"AC result shows RMS")
on.charIn("0");on.charIn("3");assert(painted("CHOOSE COMPONENT"))
on.arrowDown();on.enterKey();assert(painted("MEASUREMENT"))
assert(painted("DC CURRENT"))
on.charIn("0");on.charIn("4");assert(painted("CHOOSE COMPONENT"))
on.arrowDown();on.enterKey();assert(painted("AC CURRENT"))
on.charIn("0");on.charIn("5");assert(painted("ANALYSIS"))
on.escapeKey()
on.restore({circuit=L.demoDivider(),cx=7,cy=4,tool=1,dir=1})
on.charIn("0");on.charIn("1");on.enterKey()
assert(painted("PICK TWO NODES"),"unconnected node must not advance measurement")
on.backspaceKey();assert(#on.save().circuit.parts==4,"Del cannot remove parts in measurement mode")
on.escapeKey()

-- The responsive layout keeps each screen inside smaller calculator windows.
for _,sz in ipairs({{320,180},{240,160},{240,140}}) do
  screenW,screenH=sz[1],sz[2];on.resize(screenW,screenH)
  on.restore(saved);assert(painted("CIRCUIT LAB"))
  on.charIn("8");assert(painted("COMPONENTS"))
  on.escapeKey();on.charIn("7");assert(painted("HELP"))
  on.escapeKey();assert(painted("CIRCUIT LAB"))
  on.charIn("0");assert(painted("CHOOSE MEASUREMENT"))
  on.charIn("3");assert(painted("CHOOSE COMPONENT"))
  on.enterKey();assert(painted("MEASUREMENT"))
  on.escapeKey();assert(painted("CIRCUIT LAB"))
  on.charIn("4");assert(painted("ANALYSIS"))
  on.escapeKey();on.arrowLeft();on.arrowUp();on.charIn("5");assert(painted("PART SETTINGS"))
  on.enterKey();assert(painted("ENTER VALUE"))
  assert(widget.y>=0 and widget.y+widget.h<=screenH,"native input must fit window")
  on.escapeKey();assert(painted("PART SETTINGS"))
  on.escapeKey();on.escapeKey();assert(painted("H1 CIRCUIT LAB"))
  on.restore({circuit=L.new(),cx=4,cy=2,tool=1,dir=1})
  assert(L.place(on.save().circuit,"Q",node(4,2),1))
  on.charIn("5");assert(painted("PART SETTINGS"))
  on.escapeKey()
end
print("ALL CIRCUIT LAB TESTS PASSED")
