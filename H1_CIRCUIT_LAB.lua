-- H1 Circuit Lab: free-form grid schematic and DC / linearized AC analysis.
-- TI-Nspire CX/CX CAS Lua ScriptApp. Values are SI units.
if platform then platform.apiLevel="2.3" end

LabCore={}
local L=LabCore
L.NX=8; L.NY=5; L.MAX=40
L.tools={"SELECT","WIRE","RESISTOR","CAPACITOR","V SOURCE","I SOURCE","DIODE","BJT NPN","NMOS","JFET","GROUND","IN PROBE","OUT PROBE"}
L.toolKind={nil,"W","R","C","V","I","D","Q","M","J","G","PIN","POUT"}

function L.node(x,y)
  if x<0 or x>=L.NX or y<0 or y>=L.NY then return nil end
  return 1+y*L.NX+x
end
function L.xy(n) return (n-1)%L.NX,math.floor((n-1)/L.NX) end
function L.neighbor(n,dir)
  local x,y=L.xy(n)
  if dir==1 then return L.node(x+1,y)
  elseif dir==2 then return L.node(x,y+1)
  elseif dir==3 then return L.node(x-1,y)
  else return L.node(x,y-1) end
end
local function turn(dx,dy,dir)
  for _=2,dir do dx,dy=-dy,dx end
  return dx,dy
end
function L.terminals(n,dir)
  local x,y=L.xy(n)
  local ax,ay=turn(-1,0,dir);local bx,by=turn(0,-1,dir);local cx,cy=turn(0,1,dir)
  local a=L.node(x+ax,y+ay);local b=L.node(x+bx,y+by);local c=L.node(x+cx,y+cy)
  if not (a and b and c) then return nil end
  return a,b,c
end
function L.new()
  return {parts={},nextid=1,counts={},ground={},pin=nil,pout=nil,freq=1000}
end
function L.parse(s)
  s=tostring(s or ""):gsub("%s+",""):gsub(",","."):gsub("−","-"):gsub("@E","e"):gsub("µ","u")
  local suffix=s:sub(-1); local mult={G=1e9,M=1e6,k=1e3,K=1e3,m=1e-3,u=1e-6,n=1e-9,p=1e-12}
  local factor=mult[suffix] or 1
  if mult[suffix] then s=s:sub(1,-2) end
  local v=tonumber(s)
  if not v then return nil end
  v=v*factor
  if v~=v or v==math.huge or v==-math.huge then return nil end
  return v
end
function L.fmt(v)
  if v==nil then return "--" end
  if v~=v then return "invalid" end
  if v==math.huge or v==-math.huge then return "overflow" end
  local a=math.abs(v); local k=1; local s=""
  if a>=1e9 then k=1e9;s="G" elseif a>=1e6 then k=1e6;s="M"
  elseif a>=1e3 then k=1e3;s="k" elseif a>=1 then
  elseif a>=1e-3 then k=1e-3;s="m" elseif a>=1e-6 then k=1e-6;s="u"
  elseif a>=1e-9 then k=1e-9;s="n" elseif a>0 then k=1e-12;s="p" end
  return string.format("%.4g",v/k)..s
end
local defaults={R={value=1000},C={value=1e-6},V={value=12,ac=0},I={value=0.001,ac=0},D={is=1e-12,vt=0.026},Q={beta=100,betar=1,is=1e-15,vt=0.026},M={kn=0.001,vth=2},J={idss=0.01,vp=-4},W={},G={}}
local fields={
  R={{"value","Resistance (ohm)","pos"}},
  C={{"value","Capacitance (F)","pos"}},
  V={{"value","DC voltage (V)","any"},{"ac","AC peak (V)","any"}},
  I={{"value","DC current (A)","any"},{"ac","AC peak (A)","any"}},
  D={{"is","Sat current Is (A)","pos"},{"vt","Thermal VT (V)","pos"}},
  Q={{"beta","Forward beta","pos"},{"betar","Reverse beta","pos"},{"is","Sat current Is (A)","pos"},{"vt","Thermal VT (V)","pos"}},
  M={{"kn","NMOS kn (A/V^2)","pos"},{"vth","Threshold VT (V)","pos"}},
  J={{"idss","JFET IDSS (A)","pos"},{"vp","Pinch-off VP (V)","neg"}}
}
L.fields=fields
function L.validateField(kind,key,v)
  if type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return false,"Enter a finite number" end
  for _,f in ipairs(fields[kind] or {}) do
    if f[1]==key then
      if f[3]=="pos" and v<=0 then return false,"Must be greater than zero" end
      if f[3]=="neg" and v>=0 then return false,"VP must be negative" end
      return true
    end
  end
  return false,"Unknown property"
end
local function copyDefaults(kind)
  local o={}
  for k,v in pairs(defaults[kind] or {}) do o[k]=v end
  return o
end
local function occEdges(p)
  if p.kind=="G" then return {} end
  if p.kind=="Q" or p.kind=="M" or p.kind=="J" then
    return {{p.anchor,p.b},{p.anchor,p.c},{p.anchor,p.a}}
  end
  return {{p.a,p.b}}
end
local function sameEdge(a,b,c,d) return (a==c and b==d) or (a==d and b==c) end
function L.partAt(c,n)
  for i,p in ipairs(c.parts) do
    if p.anchor==n or p.a==n or p.b==n or p.c==n then return p,i end
  end
  return nil
end
function L.place(c,kind,n,dir)
  if not n then return nil,"Choose a grid node" end
  local allowed={W=true,R=true,C=true,V=true,I=true,D=true,Q=true,M=true,J=true,G=true,PIN=true,POUT=true}
  if not allowed[kind] then return nil,"Unknown part" end
  for _,old in ipairs(c.parts) do
    if (old.kind=="Q" or old.kind=="M" or old.kind=="J") and old.anchor==n then
      return nil,"Transistor center is not a node"
    end
  end
  if kind=="PIN" then c.pin=n;return true end
  if kind=="POUT" then c.pout=n;return true end
  if kind=="G" then c.ground[n]=true;return true end
  if #c.parts>=30 then return nil,"Limit: 30 parts on handheld" end
  local p={kind=kind,id=c.nextid,anchor=n,dir=dir or 1}
  if kind=="Q" or kind=="M" or kind=="J" then
    if c.ground[n] or c.pin==n or c.pout==n then return nil,"Move ground/probe from transistor center" end
    p.a,p.b,p.c=L.terminals(n,p.dir)
    if not p.a then return nil,"3-pin part needs room around it" end
  else
    local dest=L.neighbor(n,p.dir)
    if not dest then return nil,"Move cursor away from edge" end
    p.a=n;p.b=dest
  end
  if kind~="W" then
    local ix=({R="R",C="C",V="V",I="I",D="D",Q="Q",M="M",J="J"})[kind]
    c.counts=c.counts or {}
    p.name=ix..tostring((c.counts[ix] or 0)+1)
    local d=copyDefaults(kind)
    for k,v in pairs(d) do p[k]=v end
  end
  for _,old in ipairs(c.parts) do
    if old.anchor==n and (kind=="Q" or kind=="M" or kind=="J" or old.kind=="Q" or old.kind=="M" or old.kind=="J") then
      return nil,"Position occupied"
    end
    local newThree=kind=="Q" or kind=="M" or kind=="J"
    local oldThree=old.kind=="Q" or old.kind=="M" or old.kind=="J"
    if oldThree and (p.a==old.anchor or p.b==old.anchor or p.c==old.anchor) then return nil,"Transistor center is blocked" end
    if newThree and (old.a==p.anchor or old.b==p.anchor or old.c==p.anchor) then return nil,"Transistor center is blocked" end
    for _,e in ipairs(occEdges(p)) do
      for _,f in ipairs(occEdges(old)) do
        if sameEdge(e[1],e[2],f[1],f[2]) then return nil,"Edge occupied; select or delete it" end
      end
    end
  end
  c.parts[#c.parts+1]=p;c.nextid=c.nextid+1
  if p.name then
    local ix=p.name:sub(1,1)
    c.counts[ix]=(c.counts[ix] or 0)+1
  end
  return p
end
function L.rotate(c,p)
  if not (p and (p.kind=="Q" or p.kind=="M" or p.kind=="J")) then return nil,"Select a transistor" end
  local dir=(p.dir or 1)%4+1
  local a,b,cc=L.terminals(p.anchor,dir)
  if not a then return nil,"No room for that direction" end
  local proposed={kind=p.kind,anchor=p.anchor,a=a,b=b,c=cc}
  for _,old in ipairs(c.parts) do if old~=p then
    if old.kind=="Q" or old.kind=="M" or old.kind=="J" then
      if a==old.anchor or b==old.anchor or cc==old.anchor then return nil,"Another transistor center blocks rotation" end
    end
    for _,e in ipairs(occEdges(proposed)) do for _,f in ipairs(occEdges(old)) do
      if sameEdge(e[1],e[2],f[1],f[2]) then return nil,"An occupied branch blocks rotation" end
    end end
  end end
  p.dir=dir;p.a=a;p.b=b;p.c=cc
  return true
end
function L.remove(c,p)
  for i,v in ipairs(c.parts) do if v==p then table.remove(c.parts,i);return true end end
  return false
end

local function root(parent,n)
  while parent[n]~=n do parent[n]=parent[parent[n]];n=parent[n] end
  return n
end
local function union(parent,a,b)
  a=root(parent,a);b=root(parent,b)
  if a~=b then parent[b]=a end
end
local function network(c)
  local parent={}
  for n=1,L.NX*L.NY do parent[n]=n end
  for _,p in ipairs(c.parts) do if p.kind=="W" then union(parent,p.a,p.b) end end
  local g=nil
  for n,on in pairs(c.ground) do if on then if g then union(parent,g,n) else g=n end end end
  if not g then return nil,"Add a ground symbol first" end
  local gr=root(parent,g);local needed={}
  for _,p in ipairs(c.parts) do
    for _,n in ipairs({p.a,p.b,p.c}) do needed[root(parent,n)]=true end
  end
  if c.pin then needed[root(parent,c.pin)]=true end
  if c.pout then needed[root(parent,c.pout)]=true end
  local nodes={};local roots={}
  for r in pairs(needed) do if r~=gr then roots[#roots+1]=r end end
  table.sort(roots)
  for i,r in ipairs(roots) do nodes[r]=i end
  local nv=0
  for _,p in ipairs(c.parts) do if p.kind=="V" then nv=nv+1;p._var=#roots+nv end end
  local net={parent=parent,ground=gr,map=nodes,n=#roots+nv,nnode=#roots,roots=roots}
  function net.idx(n) if not n then return nil end return nodes[root(parent,n)] end
  return net
end

local function checkDCPath(c,net)
  local graph={}
  local function link(a,b)
    local x=root(net.parent,a);local y=root(net.parent,b)
    if not graph[x] then graph[x]={} end
    if not graph[y] then graph[y]={} end
    graph[x][y]=true;graph[y][x]=true
  end
  for _,p in ipairs(c.parts) do
    local k=p.kind
    if k=="R" or k=="V" or k=="D" then link(p.a,p.b)
    elseif k=="Q" then link(p.a,p.b);link(p.a,p.c)
    elseif k=="M" or k=="J" then link(p.b,p.c) end
  end
  local seen={[net.ground]=true};local queue={net.ground};local head=1
  while head<=#queue do
    local r=queue[head];head=head+1
    for other in pairs(graph[r] or {}) do
      if not seen[other] then seen[other]=true;queue[#queue+1]=other end
    end
  end
  for _,r in ipairs(net.roots) do
    if not seen[r] then return nil,"Floating node at DC; add bias/ground path" end
  end
  return true
end

local function zeros(n)
  local v={};for i=1,n do v[i]=0 end;return v
end
local function gaussian(a,b,n)
  local m={};local v={}
  for i=1,n do
    m[i]={};for j=1,n do m[i][j]=a[i][j] or 0 end
    v[i]=b[i] or 0
  end
  for k=1,n do
    local pivot=k;local best=math.abs(m[k][k])
    for i=k+1,n do if math.abs(m[i][k])>best then best=math.abs(m[i][k]);pivot=i end end
    if best<1e-16 then return nil,"Singular circuit; check ground and floating nodes" end
    m[k],m[pivot]=m[pivot],m[k];v[k],v[pivot]=v[pivot],v[k]
    for i=k+1,n do
      local t=m[i][k]/m[k][k]
      if t~=0 then
        for j=k+1,n do m[i][j]=m[i][j]-t*m[k][j] end
        v[i]=v[i]-t*v[k];m[i][k]=0
      end
    end
  end
  local x=zeros(n)
  for i=n,1,-1 do
    local z=v[i]
    for j=i+1,n do z=z-m[i][j]*x[j] end
    x[i]=z/m[i][i]
    if x[i]~=x[i] or x[i]==math.huge or x[i]==-math.huge then return nil,"Numeric overflow" end
  end
  return x
end
local function expLimited(z)
  return math.exp(math.max(-40,math.min(40,z)))
end
local function mosCurrent(kind,p,vg,vd,vs)
  local vgs=vg-vs;local vds=vd-vs
  local vt=kind=="M" and p.vth or p.vp
  local kn=kind=="M" and p.kn or p.idss/(p.vp*p.vp)
  if vgs<=vt then return 0,"CUTOFF",0 end
  local over=vgs-vt
  if vds>=over then return kn*over*over,"SATURATION",2*kn*over end
  if vds>=0 then return kn*(2*over*vds-vds*vds),"TRIODE",2*kn*vds end
  return -kn*(2*over*(-vds)-vds*vds),"REVERSE/INVALID",0
end
local function deviceCurrents(p,net,x)
  local function val(n) local i=net.idx(n);return i and x[i] or 0 end
  if p.kind=="D" then
    return p.is*(expLimited((val(p.a)-val(p.b))/p.vt)-1)
  elseif p.kind=="Q" then
    local vbe=val(p.a)-val(p.c)
    local vbc=val(p.a)-val(p.b)
    local af=p.beta/(p.beta+1);local ar=p.betar/(p.betar+1)
    local forward=p.is/af*(expLimited(vbe/p.vt)-1)
    local reverse=p.is/ar*(expLimited(vbc/p.vt)-1)
    local ic=af*forward-reverse
    local ib=(1-af)*forward+(1-ar)*reverse
    return ic,ib
  elseif p.kind=="M" or p.kind=="J" then
    return mosCurrent(p.kind,p,val(p.a),val(p.b),val(p.c))
  end
  return 0
end
local function residual(c,net,x,level)
  local f=zeros(net.n)
  local function at(n) local i=net.idx(n);return i and x[i] or 0 end
  local function stamp(a,b,current)
    local ia=net.idx(a);local ib=net.idx(b)
    if ia then f[ia]=f[ia]+current end
    if ib then f[ib]=f[ib]-current end
  end
  for i=1,net.nnode do f[i]=1e-10*x[i] end
  for _,p in ipairs(c.parts) do
    local k=p.kind
    if k=="R" then stamp(p.a,p.b,(at(p.a)-at(p.b))/p.value)
    elseif k=="I" then stamp(p.a,p.b,level*p.value)
    elseif k=="V" then
      stamp(p.a,p.b,x[p._var])
      f[p._var]=at(p.a)-at(p.b)-level*p.value
    elseif k=="D" then stamp(p.a,p.b,deviceCurrents(p,net,x))
    elseif k=="Q" then
      local ic,ib=deviceCurrents(p,net,x)
      stamp(p.b,p.c,ic);stamp(p.a,p.c,ib)
    elseif k=="M" or k=="J" then
      stamp(p.b,p.c,deviceCurrents(p,net,x))
    end
  end
  return f
end
local function jacobian(c,net,x,level,base)
  local a={};for i=1,net.n do a[i]={} end
  for j=1,net.n do
    local h=1e-5*math.max(1,math.abs(x[j]))
    if j>net.nnode then h=1e-7*math.max(1,math.abs(x[j])) end
    local old=x[j];x[j]=old+h
    local shifted=residual(c,net,x,level)
    x[j]=old
    for i=1,net.n do a[i][j]=(shifted[i]-base[i])/h end
  end
  return a
end
local function norm(f,net)
  local m=0
  for i,v in ipairs(f) do
    local scale=i<=net.nnode and 0.001 or 1
    local q=math.abs(v)/scale
    if q>m then m=q end
  end
  return m
end
local function dcSolve(c,net)
  local x=zeros(net.n)
  for stage=1,10 do
    local level=stage/10;local converged=false
    for _=1,45 do
      local f=residual(c,net,x,level);local score=norm(f,net)
      if score<1e-8 then converged=true;break end
      local a=jacobian(c,net,x,level,f)
      local rhs={};for i=1,net.n do rhs[i]=-f[i] end
      local dx,err=gaussian(a,rhs,net.n)
      if not dx then return nil,err end
      local step=1;local accepted=false
      for _=1,18 do
        local trial={}
        for i=1,net.n do trial[i]=x[i]+step*dx[i] end
        if norm(residual(c,net,trial,level),net)<score then x=trial;accepted=true;break end
        step=step/2
      end
      if not accepted then return nil,"DC bias did not converge" end
    end
    if not converged and norm(residual(c,net,x,level),net)>1e-7 then return nil,"DC bias did not converge" end
  end
  return x
end
local function acSolve(c,net,x)
  local n=net.n;local f=residual(c,net,x,1)
  local a=jacobian(c,net,x,1,f)
  local dim=2*n;local m={};local rhs=zeros(dim)
  for i=1,dim do m[i]={};for j=1,dim do m[i][j]=0 end end
  for i=1,n do for j=1,n do m[i][j]=a[i][j];m[n+i][n+j]=a[i][j] end end
  local omega=2*math.pi*c.freq
  local function cstamp(ia,ib,v)
    if ia then
      m[ia][n+ia]=m[ia][n+ia]-v;m[n+ia][ia]=m[n+ia][ia]+v
    end
    if ib then
      m[ib][n+ib]=m[ib][n+ib]-v;m[n+ib][ib]=m[n+ib][ib]+v
    end
    if ia and ib then
      m[ia][n+ib]=m[ia][n+ib]+v;m[ib][n+ia]=m[ib][n+ia]+v
      m[n+ia][ib]=m[n+ia][ib]-v;m[n+ib][ia]=m[n+ib][ia]-v
    end
  end
  for _,p in ipairs(c.parts) do
    if p.kind=="C" then cstamp(net.idx(p.a),net.idx(p.b),omega*p.value)
    elseif p.kind=="V" then rhs[p._var]=rhs[p._var]+p.ac
    elseif p.kind=="I" then
      local ia=net.idx(p.a);local ib=net.idx(p.b)
      if ia then rhs[ia]=rhs[ia]-p.ac end
      if ib then rhs[ib]=rhs[ib]+p.ac end
    end
  end
  local z,err=gaussian(m,rhs,dim)
  if not z then return nil,err end
  local re,im={},{};for i=1,n do re[i]=z[i];im[i]=z[n+i] end
  return {re=re,im=im}
end
local function mag(a,b) return math.sqrt(a*a+b*b) end
local function phase(a,b)
  if a==0 and b==0 then return 0 end
  if math.atan2 then return math.atan2(b,a)*180/math.pi end
  if a>0 then return math.atan(b/a)*180/math.pi end
  if a<0 then return (math.atan(b/a)+(b>=0 and math.pi or -math.pi))*180/math.pi end
  return b>0 and 90 or -90
end
local function resultLines(c,net,x,ac)
  local lines={};local function add(k,t) lines[#lines+1]={kind=k,text=t} end
  local function val(n) local i=net.idx(n);return i and x[i] or 0 end
  local function acv(n)
    local i=net.idx(n);return i and ac.re[i] or 0,i and ac.im[i] or 0
  end
  add("head","DC OPERATING POINT")
  for _,r in ipairs(net.roots) do
    local n=nil
    for k=1,L.NX*L.NY do if root(net.parent,k)==r then n=k;break end end
    local gx,gy=L.xy(n)
    add("val","N("..gx..","..gy..") = "..L.fmt(x[net.map[r]]).." V")
  end
  add("head","PART CURRENTS / REGIONS")
  for _,p in ipairs(c.parts) do
    local k=p.kind
    if k=="R" then
      local i=(val(p.a)-val(p.b))/p.value
      add("val",p.name.."  I="..L.fmt(i).."A  P="..L.fmt(i*i*p.value).."W")
    elseif k=="V" then
      add("val",p.name.."  I(+->-)="..L.fmt(x[p._var]).."A")
    elseif k=="I" then add("val",p.name.."  I="..L.fmt(p.value).."A")
    elseif k=="C" then add("val",p.name.."  DC open; V="..L.fmt(val(p.a)-val(p.b)).."V")
    elseif k=="D" then
      local i=deviceCurrents(p,net,x)
      add("val",p.name.."  ID="..L.fmt(i).."A  VD="..L.fmt(val(p.a)-val(p.b)).."V")
      if i>0 then add("note","rd="..L.fmt(p.vt/(i+p.is)).."ohm") end
    elseif k=="Q" then
      local ic,ib=deviceCurrents(p,net,x)
      local vce=val(p.b)-val(p.c)
      add("val",p.name.."  IC="..L.fmt(ic).."A  IB="..L.fmt(ib).."A")
      add("note","VBE="..L.fmt(val(p.a)-val(p.c)).."V VCE="..L.fmt(vce).."V")
      if ic>0 and vce>0.2 then add("note","ACTIVE gm="..L.fmt(ic/p.vt).."S rpi="..L.fmt(p.beta*p.vt/ic).."ohm")
      else add("warn","BJT cutoff/sat: lecture gain formula not valid") end
    elseif k=="M" or k=="J" then
      local id,region,gm=deviceCurrents(p,net,x)
      add("val",p.name.."  ID="..L.fmt(id).."A  "..region)
      add("note","VGS="..L.fmt(val(p.a)-val(p.c)).."V VDS="..L.fmt(val(p.b)-val(p.c)).."V")
      add("note","gm="..L.fmt(gm).."S")
      if region~="SATURATION" then add("warn","Not saturation: lecture gain formula not valid") end
      if k=="J" and val(p.a)>val(p.c) then add("warn","JFET gate forward bias not modeled") end
    end
  end
  add("head","AC @ "..L.fmt(c.freq).."Hz - PEAK PHASORS")
  for _,r in ipairs(net.roots) do
    local n=nil
    for k=1,L.NX*L.NY do if root(net.parent,k)==r then n=k;break end end
    local gx,gy=L.xy(n);local i=net.map[r]
    add("val","N("..gx..","..gy..") "..L.fmt(mag(ac.re[i],ac.im[i])).."V @ "..L.fmt(phase(ac.re[i],ac.im[i])).."deg")
  end
  add("head","AC BRANCH CURRENTS")
  local function signalCurrent(p,vector)
    local scale=1e-4;local shifted={}
    for i=1,net.n do shifted[i]=x[i]+scale*vector[i] end
    local one,two=deviceCurrents(p,net,x)
    local shiftedOne,shiftedTwo=deviceCurrents(p,net,shifted)
    if p.kind=="Q" then return (shiftedOne-one)/scale,(shiftedTwo-two)/scale end
    return (shiftedOne-one)/scale,nil
  end
  for _,p in ipairs(c.parts) do
    local k=p.kind
    local ra,ia=acv(p.a);local rb,ib=acv(p.b)
    local vr,vi=ra-rb,ia-ib
    local ir,ii,ibr,ibi
    if k=="R" then ir=vr/p.value;ii=vi/p.value
    elseif k=="C" then
      local b=2*math.pi*c.freq*p.value
      ir=-b*vi;ii=b*vr
    elseif k=="V" then ir=ac.re[p._var];ii=ac.im[p._var]
    elseif k=="I" then ir=p.ac;ii=0
    elseif k=="D" or k=="Q" or k=="M" or k=="J" then
      ir,ibr=signalCurrent(p,ac.re)
      ii,ibi=signalCurrent(p,ac.im)
    end
    if ir and ii then
      local name=k=="Q" and "IC" or "I"
      add("val",p.name.." "..name.."="..L.fmt(mag(ir,ii)).."A @ "..L.fmt(phase(ir,ii)).."deg")
      if ibr and ibi then add("note",p.name.." IB="..L.fmt(mag(ibr,ibi)).."A @ "..L.fmt(phase(ibr,ibi)).."deg") end
    end
    if k=="D" or k=="Q" then
      local signal
      if k=="D" then signal=mag(vr,vi)
      else
        local er,ei=acv(p.c)
        signal=mag(ra-er,ia-ei)
      end
      if signal>0.2*p.vt then add("warn",p.name.." signal >0.2 VT; small-signal may err") end
    elseif k=="M" or k=="J" then
      local er,ei=acv(p.c)
      local vgsAC=mag(ra-er,ia-ei)
      local over=val(p.a)-val(p.c)-(k=="M" and p.vth or p.vp)
      if over>0 and vgsAC>0.2*over then add("warn",p.name.." AC gate swing near overdrive") end
    end
  end
  if c.pin and c.pout then
    local ir,ii=acv(c.pin);local orr,oi=acv(c.pout)
    local den=ir*ir+ii*ii
    if den>1e-24 then
      local gr=(orr*ir+oi*ii)/den;local gi=(oi*ir-orr*ii)/den
      add("head","PROBE GAIN: OUT / IN")
      add("val","|Av|="..L.fmt(mag(gr,gi)).."  phase="..L.fmt(phase(gr,gi)).."deg")
      if mag(gr,gi)>0 then add("val","Gain="..L.fmt(20*math.log(mag(gr,gi))/math.log(10)).."dB") end
    else add("warn","IN probe has zero AC voltage; set source AC") end
  else add("note","Place IN and OUT probes to see gain") end
  add("note","Linearized AC at DC bias; no transient solver")
  return lines
end
function L.solve(c)
  if #c.parts==0 then return nil,"Place parts first" end
  if type(c.freq)~="number" or c.freq<=0 then return nil,"Frequency must be positive" end
  local net,err=network(c);if not net then return nil,err end
  if net.n>32 then return nil,"Circuit too large for handheld (32 variables)" end
  local connected;connected,err=checkDCPath(c,net)
  if not connected then return nil,err end
  local dc;dc,err=dcSolve(c,net);if not dc then return nil,err end
  local ac;ac,err=acSolve(c,net,dc);if not ac then return nil,err end
  return {net=net,dc=dc,ac=ac,lines=resultLines(c,net,dc,ac)}
end

local function activeNode(net,n)
  if not n then return false end
  local r=root(net.parent,n)
  return r==net.ground or net.map[r]~=nil
end
local function componentAt(net,vector,n)
  local i=net.idx(n)
  return i and vector[i] or 0
end
function L.measureVoltage(r,a,b,mode)
  if not activeNode(r.net,a) or not activeNode(r.net,b) then
    return nil,"Select two connected circuit nodes"
  end
  local result={kind="voltage",mode=mode,a=a,b=b,unit="V"}
  if mode=="DC" then
    result.value=componentAt(r.net,r.dc,a)-componentAt(r.net,r.dc,b)
  elseif mode=="AC" then
    local re=componentAt(r.net,r.ac.re,a)-componentAt(r.net,r.ac.re,b)
    local im=componentAt(r.net,r.ac.im,a)-componentAt(r.net,r.ac.im,b)
    result.re=re;result.im=im;result.peak=mag(re,im)
    result.rms=result.peak/math.sqrt(2);result.angle=phase(re,im)
  else return nil,"Choose DC or AC" end
  return result
end
function L.measureCurrent(c,r,p,mode)
  if not p or p.kind=="W" then return nil,"Choose a component, not a wire" end
  local net=r.net
  local dc,dcBase,ar,ai,abr,abi
  local k=p.kind
  local va=componentAt(net,r.dc,p.a);local vb=componentAt(net,r.dc,p.b)
  if k=="R" then dc=(va-vb)/p.value
  elseif k=="C" then dc=0
  elseif k=="V" then dc=r.dc[p._var]
  elseif k=="I" then dc=p.value
  elseif k=="Q" then dc,dcBase=deviceCurrents(p,net,r.dc)
  elseif k=="D" or k=="M" or k=="J" then dc=deviceCurrents(p,net,r.dc)
  else return nil,"Unsupported component" end
  local result={kind="current",mode=mode,part=p.name,partKind=k,unit="A",a=p.a,b=p.b,c=p.c,
    direction=(k=="Q" and "collector to emitter") or ((k=="M" or k=="J") and "drain to source") or "terminal A to B"}
  if mode=="DC" then
    result.value=dc;result.base=dcBase
    return result
  elseif mode~="AC" then return nil,"Choose DC or AC" end
  local ra=componentAt(net,r.ac.re,p.a);local ia=componentAt(net,r.ac.im,p.a)
  local rb=componentAt(net,r.ac.re,p.b);local ib=componentAt(net,r.ac.im,p.b)
  if k=="R" then ar=(ra-rb)/p.value;ai=(ia-ib)/p.value
  elseif k=="C" then
    local g=2*math.pi*c.freq*p.value
    ar=-g*(ia-ib);ai=g*(ra-rb)
  elseif k=="V" then ar=r.ac.re[p._var];ai=r.ac.im[p._var]
  elseif k=="I" then ar=p.ac;ai=0
  else
    local scale=1e-4
    local function shiftedCurrent(vector)
      local shifted={}
      for i=1,net.n do shifted[i]=r.dc[i]+scale*vector[i] end
      local current,base=deviceCurrents(p,net,shifted)
      if k~="Q" then base=nil end
      return (current-dc)/scale,base and (base-dcBase)/scale or nil
    end
    ar,abr=shiftedCurrent(r.ac.re)
    ai,abi=shiftedCurrent(r.ac.im)
  end
  result.re=ar;result.im=ai;result.peak=mag(ar,ai)
  result.rms=result.peak/math.sqrt(2);result.angle=phase(ar,ai)
  if abr and abi then result.basePeak=mag(abr,abi);result.baseAngle=phase(abr,abi) end
  return result
end

function L.demoDivider()
  local c=L.new()
  local function n(x,y) return L.node(x,y) end
  local v=L.place(c,"V",n(0,1),2);v.value=10;v.ac=1
  local r1=L.place(c,"R",n(0,1),1);r1.value=1000
  local r2=L.place(c,"R",n(1,1),2);r2.value=1000
  L.place(c,"W",n(1,2),3);L.place(c,"G",n(0,2),1)
  c.pin=n(0,1);c.pout=n(1,1)
  return c
end
function L.demoCE()
  local c=L.new();local function n(x,y) return L.node(x,y) end
  local v=L.place(c,"V",n(6,0),2);v.value=12
  L.place(c,"G",n(6,1),1)
  L.place(c,"W",n(5,0),1);L.place(c,"W",n(4,0),1);L.place(c,"W",n(3,0),1)
  L.place(c,"W",n(3,0),2)
  local rc=L.place(c,"R",n(4,0),2);rc.value=2200
  local q=L.place(c,"Q",n(4,2),1);q.beta=100
  local re=L.place(c,"R",n(4,3),2);re.value=1000
  L.place(c,"G",n(4,4),1)
  local r1=L.place(c,"R",n(3,1),2);r1.value=100000
  local r2=L.place(c,"R",n(3,2),2);r2.value=20000
  L.place(c,"G",n(3,3),1)
  local vi=L.place(c,"V",n(0,2),2);vi.value=0;vi.ac=0.01
  L.place(c,"G",n(0,3),1)
  local ci=L.place(c,"C",n(0,2),1);ci.value=10e-6
  L.place(c,"W",n(1,2),1);L.place(c,"W",n(2,2),1)
  c.pin=n(3,2);c.pout=n(4,1);c.freq=1000
  return c
end

-- Handheld UI: all primary actions have keypad paths; mouse is optional.
on=on or {}
local U={screen="home",homeChoice=1,circuit=L.new(),cx=2,cy=2,tool=1,dir=1,
  part=nil,field=1,scroll=1,report=nil,status="",editor=nil,editing=false,
  editTarget=nil,width=320,height=210,pending=nil,history={},
  measureChoice=1,measureMode=nil,measureStage=1,measureA=nil,measurement=nil,measureIndex=1}
local choices={"Draw / continue","Measure DC or AC","New blank circuit","Voltage divider example","BJT CE example","Help / controls"}
local measureChoices={"DC VOLTAGE  (two nodes)","AC VOLTAGE  (two nodes)",
  "DC CURRENT  (a part)","AC CURRENT  (a part)","FULL ANALYSIS REPORT"}
local G={}
local function layout()
  local w,h=U.width,U.height
  local top=math.max(12,math.min(18,math.floor(h*0.08)))
  local headerH=22
  local footerH=math.max(24,math.min(29,math.floor(h*0.14)))
  local contentTop=top+headerH+3
  local footerY=h-footerH
  local sx=math.max(20,math.floor((w-38)/(L.NX-1)))
  local x0=math.floor((w-sx*(L.NX-1))/2)
  local y0=contentTop+13
  local sy=math.max(12,math.floor((footerY-13-y0)/(L.NY-1)))
  local homeH=math.max(12,math.min(24,math.floor((footerY-contentTop-4)/#choices)))
  local homeY=contentTop+math.max(2,math.floor((footerY-contentTop-homeH*#choices)/2))
  local listH=math.max(14,math.min(18,math.floor((footerY-contentTop-3)/8)))
  local listRows=math.max(3,math.min(8,math.floor((footerY-contentTop-3)/listH)))
  local textRows=math.max(3,math.floor((footerY-contentTop-3)/17))
  G={top=top,headerH=headerH,footerH=footerH,footerY=footerY,contentTop=contentTop,
    x0=x0,y0=y0,sx=sx,sy=sy,homeH=homeH,homeY=homeY,
    listH=listH,listRows=listRows,textRows=textRows}
end
local function redraw()
  if platform and platform.window then platform.window:invalidate() end
end
local function rgb(gc,r,g,b) gc:setColorRGB(r,g,b) end
local function rect(gc,x,y,w,h,r,g,b) rgb(gc,r,g,b);gc:fillRect(x,y,w,h) end
local function label(gc,s,x,y,size,bold)
  gc:setFont("sansserif",bold and "b" or "r",size or 9)
  gc:drawString(tostring(s),x,y,"top")
end
local function segment(gc,x1,y1,x2,y2) gc:drawLine(x1,y1,x2,y2) end
local function point(n)
  local x,y=L.xy(n);return G.x0+x*G.sx,G.y0+y*G.sy
end
local function header(gc,title,right)
  rect(gc,0,G.top,U.width,G.headerH,18,48,84)
  rgb(gc,255,255,255);label(gc,title,8,G.top+5,11,true)
  if right then rgb(gc,209,229,249);label(gc,right,math.max(130,U.width-#right*6-7),G.top+5,8,false) end
end
local function footer(gc,top,bottom)
  rect(gc,0,G.footerY,U.width,G.footerH,231,240,249)
  rgb(gc,28,54,77);label(gc,top,6,G.footerY+2,8,false)
  rgb(gc,71,94,113);label(gc,bottom,6,G.footerY+13,8,false)
end
local function setStatus(s) U.status=s or "";redraw() end
local function copyTable(src)
  if type(src)~="table" then return src end
  local dst={}
  for k,v in pairs(src) do if k~="_var" then dst[k]=copyTable(v) end end
  return dst
end
local function remember()
  U.history[#U.history+1]=copyTable(U.circuit)
  if #U.history>8 then table.remove(U.history,1) end
end
local function undo()
  if #U.history==0 then setStatus("Nothing to undo");return end
  U.circuit=table.remove(U.history)
  U.part=nil;U.report=nil;U.measurement=nil;U.measureMode=nil
  U.screen="canvas";setStatus("Last change undone")
end
local function groundShape(gc,x,y)
  segment(gc,x,y,x,y+3)
  segment(gc,x-7,y+3,x+7,y+3)
  segment(gc,x-5,y+6,x+5,y+6)
  segment(gc,x-2,y+9,x+2,y+9)
end
local function drawTwoTerm(gc,p)
  local x1,y1=point(p.a);local x2,y2=point(p.b)
  local mx,my=(x1+x2)/2,(y1+y2)/2
  local ux,uy=(x2-x1)/math.max(1,math.abs(x2-x1)+math.abs(y2-y1)),(y2-y1)/math.max(1,math.abs(x2-x1)+math.abs(y2-y1))
  local px,py=-uy,ux
  if p.kind=="W" then
    rgb(gc,43,72,100);segment(gc,x1,y1,x2,y2);return
  end
  rgb(gc,27,58,87)
  local reach=(p.kind=="V" or p.kind=="I") and 9 or (p.kind=="D" and 7 or 12)
  segment(gc,x1,y1,mx-ux*reach,my-uy*reach)
  segment(gc,mx+ux*reach,my+uy*reach,x2,y2)
  if p.kind=="R" then
    local ox,oy=mx-ux*12,my-uy*12
    for i=1,7 do
      local nx=mx+ux*(-12+i*3)+px*(i==7 and 0 or (i%2==0 and -4 or 4))
      local ny=my+uy*(-12+i*3)+py*(i==7 and 0 or (i%2==0 and -4 or 4))
      segment(gc,ox,oy,nx,ny);ox,oy=nx,ny
    end
    segment(gc,ox,oy,mx+ux*12,my+uy*12)
  elseif p.kind=="C" then
    segment(gc,mx-ux*3-px*7,my-uy*3-py*7,mx-ux*3+px*7,my-uy*3+py*7)
    segment(gc,mx+ux*3-px*7,my+uy*3-py*7,mx+ux*3+px*7,my+uy*3+py*7)
    segment(gc,mx-ux*12,my-uy*12,mx-ux*3,my-uy*3)
    segment(gc,mx+ux*3,my+uy*3,mx+ux*12,my+uy*12)
  elseif p.kind=="V" or p.kind=="I" then
    gc:drawArc(mx-9,my-9,18,18,0,360)
    if p.kind=="V" then
      label(gc,"+",mx-ux*7-3,my-uy*7-6,8,true)
      label(gc,"-",mx+ux*7-3,my+uy*7-6,8,true)
    else
      segment(gc,mx-ux*5,my-uy*5,mx+ux*5,my+uy*5)
      segment(gc,mx+ux*5,my+uy*5,mx+ux*2+px*3,my+uy*2+py*3)
      segment(gc,mx+ux*5,my+uy*5,mx+ux*2-px*3,my+uy*2-py*3)
    end
  elseif p.kind=="D" then
    segment(gc,mx-ux*7-px*6,my-uy*7-py*6,mx+ux*5,my+uy*5)
    segment(gc,mx-ux*7+px*6,my-uy*7+py*6,mx+ux*5,my+uy*5)
    segment(gc,mx-ux*7-px*6,my-uy*7-py*6,mx-ux*7+px*6,my-uy*7+py*6)
    segment(gc,mx+ux*7-px*7,my+uy*7-py*7,mx+ux*7+px*7,my+uy*7+py*7)
  end
  rgb(gc,34,96,141)
  if math.abs(x2-x1)>0 then label(gc,p.name,mx-8,math.max(G.contentTop+2,my-19),8,true)
  else label(gc,p.name,mx+7,my-6,8,true) end
end
local function drawTransistor(gc,p)
  local x,y=point(p.anchor)
  local bx,by=point(p.a);local dx,dy=point(p.b);local sx,sy=point(p.c)
  local function pt(ox,oy)
    ox,oy=turn(ox,oy,p.dir or 1)
    return x+ox,y+oy
  end
  local function line(x1,y1,x2,y2)
    local ax,ay=pt(x1,y1);local bx2,by2=pt(x2,y2)
    segment(gc,ax,ay,bx2,by2)
  end
  rgb(gc,29,61,91)
  local ax,ay=pt(-11,0);local cx,cy=pt(7,-9);local ex,ey=pt(7,9)
  segment(gc,bx,by,ax,ay)
  segment(gc,dx,dy,cx,cy)
  segment(gc,sx,sy,ex,ey)
  gc:drawArc(x-11,y-11,22,22,0,360)
  if p.kind=="Q" then
    line(-11,0,-5,0)
    line(-5,-7,-5,7)
    line(-5,-5,7,-9)
    line(-5,5,7,9)
    line(5,6,8,9)
  else
    line(-11,0,-6,0)
    line(-6,-6,-6,6)
    line(3,-7,3,7)
    line(3,-7,7,-9)
    line(3,7,7,9)
    if p.kind=="J" then
      line(-6,0,3,0)
      line(-1,-3,3,0)
      line(-1,3,3,0)
    end
  end
  rgb(gc,34,96,141)
  local lx,ly=pt(11,-8)
  label(gc,p.name,lx,ly,8,true)
end
local function drawGrid(gc)
  rect(gc,0,G.contentTop,U.width,G.footerY-G.contentTop,252,253,255)
  for gy=0,L.NY-1 do for gx=0,L.NX-1 do
    local x,y=point(L.node(gx,gy))
    rgb(gc,201,213,226);gc:fillArc(x-1,y-1,3,3,0,360)
  end end
  for _,p in ipairs(U.circuit.parts) do
    if p.kind=="Q" or p.kind=="M" or p.kind=="J" then drawTransistor(gc,p)
    else drawTwoTerm(gc,p) end
  end
  for n,on in pairs(U.circuit.ground) do if on then local x,y=point(n);rgb(gc,32,72,99);groundShape(gc,x,y) end end
  if U.circuit.pin then local x,y=point(U.circuit.pin);rgb(gc,17,130,75);label(gc,"IN",x-10,math.max(G.contentTop+2,y-15),8,true) end
  if U.circuit.pout then local x,y=point(U.circuit.pout);rgb(gc,192,65,41);label(gc,"OUT",x-12,y+5,8,true) end
  local n=L.node(U.cx,U.cy);local x,y=point(n)
  rgb(gc,221,113,25);gc:drawRect(x-7,y-7,14,14)
  if U.measureA and U.measureMode and U.measureMode:sub(-1)=="V" then
    local ax,ay=point(U.measureA)
    rgb(gc,20,135,87);gc:drawRect(ax-10,ay-10,20,20)
  end
  local kind=L.toolKind[U.tool]
  if not U.measureMode and kind and kind~="G" and kind~="PIN" and kind~="POUT" and kind~="Q" and kind~="M" and kind~="J" then
    local other=L.neighbor(n,U.dir)
    if other then local xx,yy=point(other);rgb(gc,242,159,69);segment(gc,x,y,xx,yy) end
  end
end
local function paintHome(gc)
  header(gc,"H1 CIRCUIT LAB","BUILD + MEASURE")
  for i,title in ipairs(choices) do
    local y=G.homeY+(i-1)*G.homeH
    if i==U.homeChoice then rect(gc,8,y,U.width-16,G.homeH,210,231,250) end
    rgb(gc,i==U.homeChoice and 14 or 49,71,105)
    label(gc,title,17,y+2,9,i==U.homeChoice)
  end
  footer(gc,"Arrows move selection  |  Enter open",U.status~="" and U.status or "Existing drawing is saved in document")
end
local function terminalGuide(kind,dir)
  local a,b,c=L.terminals(L.node(3,2),dir)
  local center=L.node(3,2)
  local function rel(n)
    local x,y=L.xy(n);local xx,yy=L.xy(center)
    if x<xx then return "L" elseif x>xx then return "R" elseif y<yy then return "U" else return "D" end
  end
  return (kind=="Q" and "B:" or "G:")..rel(a).." "..(kind=="Q" and "C:" or "D:")..rel(b).." "..(kind=="Q" and "E:" or "S:")..rel(c)
end
local function paintCanvas(gc)
  local kind=L.toolKind[U.tool]
  local measuring=U.measureMode and U.measureMode:sub(-1)=="V"
  header(gc,measuring and "PICK TWO NODES" or "CIRCUIT LAB",
    measuring and (U.measureMode:sub(1,2).." VOLTAGE") or (L.tools[U.tool].."  "..U.dir.."/4"))
  drawGrid(gc)
  if measuring then
    footer(gc,U.measureStage==1 and "Enter: choose + node" or "Enter: choose - node",
      U.status~="" and U.status or ("Cursor N("..U.cx..","..U.cy..")  |  Esc cancel"))
    return
  end
  local bottom="3 rotate  5 edit  Del remove  7 help"
  if kind=="Q" or kind=="M" or kind=="J" then bottom=terminalGuide(kind,U.dir).."  |  3 rotate" end
  if U.report then
    local n=L.node(U.cx,U.cy);local i=U.report.net.idx(n)
    if i or root(U.report.net.parent,n)==U.report.net.ground then
      local dc=i and U.report.dc[i] or 0
      local ac=i and math.sqrt(U.report.ac.re[i]^2+U.report.ac.im[i]^2) or 0
      bottom="CURSOR: DC "..L.fmt(dc).."V   AC "..L.fmt(ac).."V peak"
    else bottom="CURSOR: unconnected grid point" end
  end
  footer(gc,"0 MEASURE  8 parts  Enter place  4 report",U.status~="" and U.status or bottom)
end
local function measurePartList()
  local parts={}
  for _,p in ipairs(U.circuit.parts) do if p.kind~="W" then parts[#parts+1]=p end end
  return parts
end
local function paintMeasureMenu(gc)
  header(gc,"CHOOSE MEASUREMENT","DC / AC")
  local rowH=math.max(13,math.min(27,math.floor((G.footerY-G.contentTop-7)/#measureChoices)))
  local firstY=G.contentTop+math.max(3,math.floor((G.footerY-G.contentTop-rowH*#measureChoices)/2))
  for i,title in ipairs(measureChoices) do
    local y=firstY+(i-1)*rowH
    if i==U.measureChoice then rect(gc,8,y,U.width-16,rowH,210,231,250) end
    rgb(gc,i==U.measureChoice and 15 or 52,70,103)
    label(gc,tostring(i).."  "..title,15,y+3,9,i==U.measureChoice)
  end
  footer(gc,"Up/Down choose  Enter open",U.status~="" and U.status or "Esc: back")
end
local function paintMeasureParts(gc)
  header(gc,"CHOOSE COMPONENT",U.measureMode=="DCI" and "DC CURRENT" or "AC CURRENT")
  local parts=measurePartList()
  local names={R="Resistor",C="Capacitor",V="V source",I="I source",
    D="Diode",Q="BJT NPN",M="NMOS",J="JFET"}
  if #parts==0 then
    rgb(gc,63,80,97);label(gc,"No measurable parts yet.",12,G.contentTop+12,10,false)
  else
    local first=math.max(1,math.min(U.measureIndex-3,#parts-G.listRows+1))
    for i=first,math.min(#parts,first+G.listRows-1) do
      local p=parts[i];local y=G.contentTop+2+(i-first)*G.listH
      if i==U.measureIndex then rect(gc,7,y-1,U.width-14,G.listH,210,231,250) end
      rgb(gc,i==U.measureIndex and 14 or 52,72,102)
      local val=p.value or p.beta or p.kn or p.idss or p.is
      label(gc,p.name.."  "..(names[p.kind] or p.kind)..(val and ("  "..L.fmt(val)) or ""),13,y,9,i==U.measureIndex)
    end
  end
  footer(gc,"Up/Down part  Enter measure",U.status~="" and U.status or "Esc: measurement menu")
end
local function nodeText(n)
  local x,y=L.xy(n);return "N("..x..","..y..")"
end
local function paintMeasureResult(gc)
  local m=U.measurement
  if not m then U.screen="canvas";paintCanvas(gc);return end
  header(gc,"MEASUREMENT",m.mode..(m.kind=="voltage" and " VOLTAGE" or " CURRENT"))
  local y=G.contentTop+3
  rgb(gc,43,66,91)
  if m.kind=="voltage" then label(gc,nodeText(m.a).." (+)  -  "..nodeText(m.b).." (-)",12,y,9,true)
  else label(gc,m.part.."  "..m.direction,12,y,9,true) end
  rect(gc,9,y+20,U.width-18,30,219,235,250)
  rgb(gc,12,65,117)
  label(gc,m.mode=="DC" and ("= "..L.fmt(m.value).." "..m.unit)
    or ("Peak = "..L.fmt(m.peak).." "..m.unit),16,y+24,15,true)
  rgb(gc,47,69,91)
  if m.mode=="AC" then
    label(gc,"RMS = "..L.fmt(m.rms).." "..m.unit,12,y+53,9,false)
    label(gc,"Phase "..L.fmt(m.angle).." deg   f="..L.fmt(U.circuit.freq).."Hz",12,y+67,9,false)
  elseif m.kind=="current" then
    local text=m.partKind=="Q" and ("Base current = "..L.fmt(m.base).." A")
      or (nodeText(m.a).." -> "..nodeText(m.b))
    label(gc,text,12,y+53,9,false)
    label(gc,"Negative value means opposite flow",12,y+67,8,false)
  else
    label(gc,"Positive: first node is higher",12,y+53,9,false)
    label(gc,"Negative: second node is higher",12,y+67,8,false)
  end
  local bottom="Esc: return to drawing"
  if m.mode=="AC" and m.peak==0 then bottom="AC is zero: set source AC peak"
  elseif m.mode=="AC" and m.basePeak then bottom="BJT base peak = "..L.fmt(m.basePeak).." A" end
  footer(gc,"0 new measure  Enter drawing",bottom)
end
local function paintPalette(gc)
  header(gc,"COMPONENTS","ARROWS + ENTER")
  local first=math.max(1,math.min(U.tool-3,#L.tools-G.listRows+1))
  for i=first,math.min(#L.tools,first+G.listRows-1) do
    local y=G.contentTop+2+(i-first)*G.listH
    if i==U.tool then rect(gc,6,y-1,U.width-12,G.listH,213,231,250) end
    rgb(gc,i==U.tool and 17 or 52,77,111)
    label(gc,tostring(i).."  "..L.tools[i],13,y,9,i==U.tool)
  end
  footer(gc,"Enter chooses tool  |  Esc drawing","Place at highlighted grid node")
end
local function paintProps(gc)
  local p=U.part
  if not p then U.screen="canvas";paintCanvas(gc);return end
  header(gc,"PART SETTINGS",p.name.."  "..p.kind)
  rgb(gc,50,68,86);label(gc,"Up/Down: value  Left/Right: part",10,G.contentTop+1,8,false)
  local fs=L.fields[p.kind] or {}
  local rowH=math.max(15,math.min(31,math.floor((G.footerY-G.contentTop-22)/math.max(1,#fs))))
  local firstY=G.contentTop+20
  for i,f in ipairs(fs) do
    local y=firstY+(i-1)*rowH
    if i==U.field then rect(gc,8,y-1,U.width-16,rowH-1,213,232,250) end
    rgb(gc,39,65,84);label(gc,f[2],15,y,9,false)
    rgb(gc,11,87,141);label(gc,L.fmt(p[f[1]]),U.width-72,y,9,true)
  end
  local isThree=p.kind=="Q" or p.kind=="M" or p.kind=="J"
  footer(gc,isThree and "3 rotate  Enter edit  Del delete" or "Enter edit  Del delete  Esc back",
    isThree and terminalGuide(p.kind,p.dir or 1).."  |  Esc back" or "Up/Down value  Left/Right part")
end
local function paintEdit(gc)
  header(gc,"ENTER VALUE","native input")
  local title=U.editTarget and U.editTarget.label or "Value"
  rgb(gc,38,64,85);label(gc,title,12,G.contentTop+4,10,true)
  local ey=G.contentTop+30
  rgb(gc,83,108,127);label(gc,"Type value, then Enter. Esc cancels.",12,ey+33,9,false)
  if G.footerY>=ey+56 then
    if U.status~="" then rgb(gc,175,39,30);label(gc,U.status,12,ey+46,9,true)
    else label(gc,"Examples: 2.2k, 10m, 1e-3",12,ey+46,9,false) end
  elseif U.status~="" then rgb(gc,175,39,30);label(gc,U.status,12,ey+33,9,true) end
  footer(gc,"Enter save  |  Esc cancel","Full calculator keypad is available")
end
local function visibleReportLines(gc)
  if U.displayLines and U.displayWidth==U.width and U.displayReport==U.report then
    return U.displayLines
  end
  local out={};local raw=U.report and U.report.lines or {}
  local width=U.width-20
  for _,item in ipairs(raw) do
    gc:setFont("sansserif",item.kind=="note" and "r" or "b",item.kind=="note" and 8 or 9)
    local rest=item.text;local first=true
    repeat
      local cut=#rest
      while cut>1 and gc:getStringWidth(rest:sub(1,cut))>width do cut=cut-1 end
      if cut<#rest then
        local space=rest:sub(1,cut):match("^.*() ")
        if space and space>math.floor(cut/2) then cut=space end
      end
      local piece=rest:sub(1,cut):gsub("%s+$","")
      out[#out+1]={kind=first and item.kind or "note",text=piece}
      rest=rest:sub(cut+1):gsub("^%s+","")
      first=false
    until rest==""
  end
  U.displayLines=out
  U.displayWidth=U.width;U.displayReport=U.report
  return out
end
local function paintResults(gc)
  header(gc,"ANALYSIS","DC + AC  "..L.fmt(U.circuit.freq).."Hz")
  local lines=visibleReportLines(gc)
  U.scroll=math.max(1,math.min(U.scroll,math.max(1,#lines-G.textRows+1)))
  for i=1,G.textRows do
    local item=lines[U.scroll+i-1]
    if item then
      local y=G.contentTop+2+(i-1)*17
      if item.kind=="head" then
        rect(gc,5,y-1,U.width-10,16,218,233,248)
        rgb(gc,24,67,111);label(gc,item.text,9,y,9,true)
      elseif item.kind=="warn" then rgb(gc,174,51,32);label(gc,item.text,9,y,9,true)
      elseif item.kind=="val" then rgb(gc,28,65,91);label(gc,item.text,9,y,9,true)
      else rgb(gc,75,91,106);label(gc,item.text,10,y,8,false) end
    end
  end
  footer(gc,"Up/Down scroll  Left/Right page",U.scroll.." / "..#lines.."  |  0 measure  Esc drawing")
end
local help={
  "0: MEASURE after building a circuit.",
  "Choose DC/AC voltage or current.",
  "Voltage: Enter on + node, then - node.",
  "Current: choose a component by name.",
  "AC shows peak, RMS, phase, frequency.",
  "Current sign follows listed direction.",
  "4: full DC+AC analysis report.",
  "DRAW: arrows move the orange cursor.",
  "8: parts list. Up/Down, Enter select.",
  "1/2 or Tab: previous/next tool.",
  "3: rotate BEFORE placing any part.",
  "BJT/MOS/JFET: 4 orientations.",
  "B/G, C/D, E/S shown in footer.",
  "Enter: put part at cursor node.",
  "WIRE joins neighboring grid points.",
  "SELECT+Enter or 5: part settings.",
  "In settings: 3 rotates transistor.",
  "In settings: Enter edits a value.",
  "Del/Backspace: delete selected part.",
  "At grid node, Del removes probe/GND.",
  "6: set AC frequency.",
  "9: undo the last change (8 levels).",
  "7: this help. Esc: back/menu.",
  "Results: Up/Down scroll; arrows page.",
  "IN/OUT probes measure AC gain.",
  "Source DC and AC peak are separate.",
  "GROUND defines zero volts; required.",
  "3-pin center grid point is blocked."
}
local function paintHelp(gc)
  header(gc,"HELP","KEYPAD GUIDE")
  for i=1,G.textRows do
    local s=help[U.scroll+i-1]
    if s then rgb(gc,45,66,85);label(gc,s,9,G.contentTop+2+(i-1)*17,8,false) end
  end
  footer(gc,"Up/Down scroll","Esc return")
end
local function ensureEditor()
  if U.editor or not D2Editor then return end
  layout()
  local ed=D2Editor.newRichText()
  ed:move(12,G.contentTop+30);ed:resize(math.max(100,U.width-24),27)
  ed:setBorder(1);ed:setFontSize(12);ed:setVisible(false)
  U.editor=ed
  ed:registerFilter({
    enterKey=function() H1LabCommit();return true end,
    returnKey=function() H1LabCommit();return true end,
    tabKey=function() H1LabCommit();return true end,
    escapeKey=function() H1LabCancel();return true end
  })
end
local function startEdit(target)
  ensureEditor()
  if not U.editor then setStatus("Native input not available");return end
  U.editTarget=target;U.editing=true;U.status="";U.screen="edit"
  U.editor:setVisible(true)
  local s=tostring(target.value)
  U.editor:setText(s,1,#s+1);U.editor:setFocus(true)
  redraw()
end
function H1LabCommit()
  if not U.editing then return end
  local t=U.editTarget;local v=L.parse(U.editor:getText())
  local ok,msg
  if t.kind=="FREQ" then ok=type(v)=="number" and v>0;msg="Frequency must be positive"
  else ok,msg=L.validateField(t.kind,t.key,v) end
  if not ok then U.status=msg or "Invalid value";redraw();return end
  remember()
  if t.kind=="FREQ" then U.circuit.freq=v else t.part[t.key]=v end
  U.editor:setFocus(false);U.editor:setVisible(false)
  U.editing=false;U.screen=t.kind=="FREQ" and "canvas" or "props"
  U.editTarget=nil;U.report=nil;U.status="Saved";redraw()
end
function H1LabCancel()
  if not U.editing then return end
  local t=U.editTarget
  U.editor:setFocus(false);U.editor:setVisible(false)
  U.editing=false;U.screen=t.kind=="FREQ" and "canvas" or "props"
  U.editTarget=nil;U.status="Cancelled";redraw()
end
local function selectedNode() return L.node(U.cx,U.cy) end
local function partsAtNode(n)
  local primary,secondary={},{}
  for _,p in ipairs(U.circuit.parts) do
    if p.kind~="W" and p.anchor==n then primary[#primary+1]=p
    elseif p.kind~="W" and (p.a==n or p.b==n or p.c==n) then secondary[#secondary+1]=p end
  end
  for _,p in ipairs(secondary) do primary[#primary+1]=p end
  return primary
end
local function selectedPart()
  local n=selectedNode()
  local list=partsAtNode(n)
  return list[1] or L.partAt(U.circuit,n)
end
local function cyclePart(delta)
  local list=partsAtNode(selectedNode())
  if #list<2 then setStatus("Only one part at this node");return end
  local index=1
  for i,p in ipairs(list) do if p==U.part then index=i;break end end
  U.part=list[(index-1+delta)%#list+1]
  if U.part.kind=="W" then U.field=1 else U.field=math.min(U.field,#L.fields[U.part.kind]) end
  U.status="";redraw()
end
local function openProps()
  local p=selectedPart()
  if not p then setStatus("No part at cursor");return end
  if p.kind=="W" then setStatus("Wire has no value; Del removes it");return end
  U.part=p;U.field=1;U.screen="props";U.status="";redraw()
end
local function placeCurrent()
  local kind=L.toolKind[U.tool]
  if not kind then openProps();return end
  local before=copyTable(U.circuit)
  local result,err=L.place(U.circuit,kind,selectedNode(),U.dir)
  if not result then setStatus(err);return end
  U.history[#U.history+1]=before
  if #U.history>8 then table.remove(U.history,1) end
  U.report=nil;setStatus((kind=="PIN" or kind=="POUT") and "Probe set" or "Placed "..kind)
end
local function ensureReport()
  if U.report then return U.report end
  local r,err=L.solve(U.circuit)
  if not r then setStatus(err);return nil end
  U.report=r
  return r
end
local function solveCurrent()
  if not ensureReport() then return end
  U.measureMode=nil;U.screen="results";U.scroll=1;U.status="";redraw()
end
local function openMeasureMenu()
  U.measureReturn=U.screen=="home" and "home" or "canvas"
  U.measureMode=nil;U.measureA=nil;U.measurement=nil
  U.screen="measureMenu";U.status="";redraw()
end
local function beginMeasurement(choice)
  U.measureChoice=choice or U.measureChoice
  U.status="";U.measureA=nil;U.measurement=nil;U.measureStage=1
  if U.measureChoice==5 then solveCurrent();return end
  U.measureMode=({"DCV","ACV","DCI","ACI"})[U.measureChoice]
  U.measureIndex=1
  U.screen=U.measureChoice<=2 and "canvas" or "measureParts"
  redraw()
end
local function chooseMeasureNode()
  local r=ensureReport();if not r then return end
  local n=selectedNode()
  if not activeNode(r.net,n) then setStatus("Choose a connected circuit node");return end
  if U.measureStage==1 then
    U.measureA=n;U.measureStage=2;setStatus("+ node chosen; select - node")
    return
  end
  local m,err=L.measureVoltage(r,U.measureA,n,U.measureMode:sub(1,2))
  if not m then setStatus(err);return end
  U.measurement=m;U.measureMode=nil;U.screen="measureResult";U.status="";redraw()
end
local function chooseMeasurePart()
  local parts=measurePartList();local p=parts[U.measureIndex]
  if not p then setStatus("Add a component first");return end
  local r=ensureReport();if not r then return end
  local m,err=L.measureCurrent(U.circuit,r,p,U.measureMode:sub(1,2))
  if not m then setStatus(err);return end
  U.measurement=m;U.measureMode=nil;U.screen="measureResult";U.status="";redraw()
end
local function activateHome()
  local i=U.homeChoice
  if i==1 then U.screen="canvas"
  elseif i==2 then openMeasureMenu()
  elseif i==6 then U.helpReturn="home";U.screen="help";U.scroll=1
  elseif i==3 or i==4 or i==5 then
    if #U.circuit.parts>0 and U.pending~=i then
      U.pending=i;setStatus("Press Enter again to replace current drawing");return
    end
    remember()
    if i==3 then U.circuit=L.new()
    elseif i==4 then U.circuit=L.demoDivider()
    else U.circuit=L.demoCE() end
    U.report=nil;U.measureMode=nil;U.measurement=nil;U.pending=nil
    U.cx=2;U.cy=2;U.screen="canvas";U.status=""
  end
  redraw()
end
function on.construction() ensureEditor() end
function on.resize(w,h)
  U.width=w or U.width;U.height=h or U.height
  layout()
  if U.editor then U.editor:move(12,G.contentTop+30);U.editor:resize(math.max(100,U.width-24),27) end
  redraw()
end
function on.paint(gc)
  if platform and platform.window then U.width=platform.window:width();U.height=platform.window:height() end
  layout()
  rect(gc,0,0,U.width,U.height,249,251,253)
  if U.screen=="home" then paintHome(gc)
  elseif U.screen=="canvas" then paintCanvas(gc)
  elseif U.screen=="props" then paintProps(gc)
  elseif U.screen=="edit" then paintEdit(gc)
  elseif U.screen=="results" then paintResults(gc)
  elseif U.screen=="help" then paintHelp(gc)
  elseif U.screen=="palette" then paintPalette(gc)
  elseif U.screen=="measureMenu" then paintMeasureMenu(gc)
  elseif U.screen=="measureParts" then paintMeasureParts(gc)
  elseif U.screen=="measureResult" then paintMeasureResult(gc) end
end
local function move(dx,dy)
  if U.editing then return end
  if U.screen=="home" then
    U.homeChoice=math.max(1,math.min(#choices,U.homeChoice+dy));U.pending=nil;U.status=""
  elseif U.screen=="canvas" then
    U.cx=math.max(0,math.min(L.NX-1,U.cx+dx))
    U.cy=math.max(0,math.min(L.NY-1,U.cy+dy));U.status=""
  elseif U.screen=="props" then
    if dx~=0 then cyclePart(dx)
    else U.field=math.max(1,math.min(#(L.fields[U.part.kind] or {}),U.field+dy)) end
  elseif U.screen=="results" then
    local d=dy~=0 and dy or dx*G.textRows
    local lines=U.displayLines or U.report.lines
    U.scroll=math.max(1,math.min(math.max(1,#lines-G.textRows+1),U.scroll+d))
  elseif U.screen=="help" then
    U.scroll=math.max(1,math.min(math.max(1,#help-G.textRows+1),U.scroll+dy))
  elseif U.screen=="palette" then
    U.tool=math.max(1,math.min(#L.tools,U.tool+dy))
  elseif U.screen=="measureMenu" then
    U.measureChoice=math.max(1,math.min(#measureChoices,U.measureChoice+dy))
  elseif U.screen=="measureParts" then
    U.measureIndex=math.max(1,math.min(#measurePartList(),U.measureIndex+dy))
  end
  redraw()
end
function on.arrowUp() move(0,-1) end
function on.arrowDown() move(0,1) end
function on.arrowLeft() move(-1,0) end
function on.arrowRight() move(1,0) end
function on.tabKey()
  if U.screen=="canvas" and not U.measureMode then U.tool=U.tool%#L.tools+1;U.status="";redraw() end
end
function on.backTabKey()
  if U.screen=="canvas" and not U.measureMode then U.tool=(U.tool-2)%#L.tools+1;U.status="";redraw() end
end
function on.enterKey()
  if U.editing then return end
  if U.screen=="home" then activateHome()
  elseif U.screen=="canvas" then
    if U.measureMode then chooseMeasureNode() else placeCurrent() end
  elseif U.screen=="props" then
    local f=L.fields[U.part.kind][U.field]
    startEdit({kind=U.part.kind,part=U.part,key=f[1],label=f[2],value=U.part[f[1]]})
  elseif U.screen=="results" then U.screen="canvas";redraw()
  elseif U.screen=="palette" then U.screen="canvas";redraw()
  elseif U.screen=="measureMenu" then beginMeasurement()
  elseif U.screen=="measureParts" then chooseMeasurePart()
  elseif U.screen=="measureResult" then U.screen="canvas";redraw() end
end
function on.returnKey() on.enterKey() end
function on.escapeKey()
  if U.editing then H1LabCancel();return end
  if U.screen=="home" then return end
  if U.screen=="help" then U.screen=U.helpReturn or "home"
  elseif U.screen=="measureParts" then U.measureMode=nil;U.screen="measureMenu"
  elseif U.screen=="measureMenu" then U.measureMode=nil;U.screen=U.measureReturn or "canvas"
  elseif U.screen=="measureResult" then U.measureMode=nil;U.screen="canvas"
  elseif U.screen=="canvas" and U.measureMode then U.measureMode=nil;U.measureA=nil;U.screen="canvas"
  elseif U.screen=="props" or U.screen=="results" or U.screen=="palette" then U.screen="canvas"
  else U.screen="home" end
  U.status="";U.pending=nil;redraw()
end
function on.deleteKey()
  if U.measureMode then setStatus("Esc cancels this measurement");return end
  if U.screen=="canvas" then
    local n=selectedNode();local p=selectedPart()
    if p then remember();L.remove(U.circuit,p);U.report=nil;setStatus("Part removed")
    elseif U.circuit.ground[n] then remember();U.circuit.ground[n]=nil;U.report=nil;setStatus("Ground removed")
    elseif U.circuit.pin==n then remember();U.circuit.pin=nil;U.report=nil;setStatus("IN probe removed")
    elseif U.circuit.pout==n then remember();U.circuit.pout=nil;U.report=nil;setStatus("OUT probe removed") end
  elseif U.screen=="props" and U.part then
    remember();L.remove(U.circuit,U.part);U.part=nil;U.screen="canvas";U.report=nil;setStatus("Part removed")
  end
end
function on.backspaceKey() on.deleteKey() end
function on.charIn(ch)
  if U.editing then return end
  local s=tostring(ch or ""):lower()
  if U.screen=="canvas" then
    if s=="0" then openMeasureMenu()
    elseif U.measureMode then return
    elseif s=="1" then U.tool=(U.tool-2)%#L.tools+1;U.status="";redraw()
    elseif s=="2" then on.tabKey()
    elseif s=="3" then U.dir=U.dir%4+1;U.status="";redraw()
    elseif s=="4" then solveCurrent()
    elseif s=="5" then openProps()
    elseif s=="6" then startEdit({kind="FREQ",label="AC frequency (Hz)",value=U.circuit.freq})
    elseif s=="7" then U.helpReturn="canvas";U.screen="help";U.scroll=1;redraw() end
    if s=="8" then U.screen="palette";U.status="";redraw() end
    if s=="9" then undo() end
  elseif U.screen=="home" then
    local n=tonumber(s)
    if n and n>=1 and n<=#choices then U.homeChoice=n;activateHome() end
  elseif U.screen=="props" and s=="3" then
    local before=copyTable(U.circuit)
    local result,err=L.rotate(U.circuit,U.part)
    if result then
      U.history[#U.history+1]=before
      if #U.history>8 then table.remove(U.history,1) end
      U.report=nil;setStatus("Rotated "..U.part.name)
    else setStatus(err) end
  elseif U.screen=="measureMenu" then
    local n=tonumber(s)
    if n and n>=1 and n<=#measureChoices then beginMeasurement(n) end
  elseif U.screen=="measureResult" and s=="0" then openMeasureMenu()
  elseif U.screen=="results" and s=="0" then openMeasureMenu()
  elseif U.screen=="results" and s=="1" then U.screen="canvas";redraw() end
end
function on.mouseDown(x,y)
  if U.editing then return end
  layout()
  if U.screen=="home" then
    local i=math.floor((y-G.homeY)/G.homeH)+1
    if y>=G.homeY and i>=1 and i<=#choices and y<G.homeY+i*G.homeH then
      U.homeChoice=i;activateHome()
    end
  elseif U.screen=="canvas" then
    if U.tool==1 and not U.measureMode then
      for _,p in ipairs(U.circuit.parts) do
        if p.kind~="W" then
          local three=p.kind=="Q" or p.kind=="M" or p.kind=="J"
          local x1,y1=point(three and p.anchor or p.a)
          local x2,y2=point(three and p.anchor or p.b)
          local mx,my=(x1+x2)/2,(y1+y2)/2
          if math.abs(x-mx)<10 and math.abs(y-my)<10 then
            local px,py=L.xy(p.anchor);U.cx=px;U.cy=py
            U.part=p;U.field=1;U.screen="props";U.status="";redraw();return
          end
        end
      end
    end
    local gx=math.floor((x-G.x0)/G.sx+0.5);local gy=math.floor((y-G.y0)/G.sy+0.5)
    if gx>=0 and gx<L.NX and gy>=0 and gy<L.NY then
      local px,py=point(L.node(gx,gy))
      if math.abs(px-x)<=13 and math.abs(py-y)<=13 then
        if U.cx==gx and U.cy==gy then
          if U.measureMode then chooseMeasureNode() else placeCurrent() end
        else U.cx=gx;U.cy=gy;U.status="";redraw() end
      end
    end
  elseif U.screen=="props" then
    local fs=L.fields[U.part.kind] or {}
    local rowH=math.max(15,math.min(31,math.floor((G.footerY-G.contentTop-22)/math.max(1,#fs))))
    local firstY=G.contentTop+20
    local i=math.floor((y-firstY)/rowH)+1
    if i>=1 and i<=#fs and y>=firstY+(i-1)*rowH and y<firstY+i*rowH then
      U.field=i;on.enterKey()
    end
  elseif U.screen=="palette" then
    local first=math.max(1,math.min(U.tool-3,#L.tools-G.listRows+1))
    local firstY=G.contentTop+1
    local i=first+math.floor((y-firstY)/G.listH)
    if y>=firstY and i>=first and i<=math.min(#L.tools,first+G.listRows-1) then
      U.tool=i;U.screen="canvas";redraw()
    end
  elseif U.screen=="measureMenu" then
    local rowH=math.max(13,math.min(27,math.floor((G.footerY-G.contentTop-7)/#measureChoices)))
    local firstY=G.contentTop+math.max(3,math.floor((G.footerY-G.contentTop-rowH*#measureChoices)/2))
    local i=math.floor((y-firstY)/rowH)+1
    if i>=1 and i<=#measureChoices and y>=firstY+(i-1)*rowH and y<firstY+i*rowH then
      beginMeasurement(i)
    end
  elseif U.screen=="measureParts" then
    local parts=measurePartList()
    local first=math.max(1,math.min(U.measureIndex-3,#parts-G.listRows+1))
    local firstY=G.contentTop+1
    local i=first+math.floor((y-firstY)/G.listH)
    if i>=first and i<=math.min(#parts,first+G.listRows-1) then
      U.measureIndex=i;chooseMeasurePart()
    end
  end
end
function on.save()
  return {circuit=U.circuit,cx=U.cx,cy=U.cy,tool=U.tool,dir=U.dir}
end
function on.restore(saved)
  if not saved then return end
  U.circuit=saved.circuit or L.new()
  U.cx=saved.cx or 2;U.cy=saved.cy or 2;U.tool=saved.tool or 1;U.dir=saved.dir or 1
  U.screen="canvas";U.report=nil;U.part=nil;U.editing=false;U.pending=nil
  U.measureMode=nil;U.measurement=nil;U.measureA=nil;U.measureStage=1;U.measureIndex=1
  U.history={}
  ensureEditor();redraw()
end
