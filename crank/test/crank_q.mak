# unit tests for crank.min

include .config
vars := $(.VARIABLES)
include $(crank)/crank.min
vars := $(filter-out vars $(vars),$(.VARIABLES))

include ../debug.min

################################
# check for namespace pollution
################################


publicClasses = V Gen Options Copy Phony Zip InferCC Exe Lib Snip Test

publicVars = <% \\% .% &% + inherit @@ @ < ^ v _v v. q. V build require get get* crank_DEBUG $(foreach c,$(publicClasses),$c.% $c_%)

$(call dbg_expect,,$(filter-out $(publicVars),$(vars)))

################################
# utilities
################################

# <parseItem>

pa = $(call dbg_expect,$(strip $1),$(strip $(call <parseItem>,$(strip $2))))

$(call pa,C=Class,             		 Class)
$(call pa,C=Class I=Item.txt,  		 Class[Item.txt])
$(call pa,C=Class I=Item.txt P=propname, Class[Item.txt].propname)

#### shorthands

A.parent = Gen
A.out = $C/$I
B.parent = A
B.in = x y z
B.at = $@
B.ca = $^
B.lt = $<

$(call dbg_expect,B/b,$(call get,at,B,b))
$(call dbg_expect,x y z,$(call get,ca,B,b))
$(call dbg_expect,x,$(call get,lt,B,b))

A.parent =


#### Inferred items

AA.parent = Gen
AA.out = aa/$I
BB.parent = AA
BB.inferredItems = AA[x]
BB.out = bb/$I
CC.inferredItems = BB[$I] AA[$I]
CC.out = cc/$I
CC.parent = Gen
CC = x y

# when multiple items infer the same item, filter out dups
$(call dbg_expect,\
  BB[x] BB[y] AA[x],\
  $(strip $(call <inferItems>,BB[x] BB[y])))

# when an item is inferred twice in different phases...
$(call dbg_expect,\
  BB[x] BB[y] AA[x],\
  $(strip $(call <inferItems>,BB[x] BB[y])))

$(call dbg_expect,\
   CC[x] CC[y] BB[x] AA[x] BB[y] AA[y],\
   $(<allItems>))

$(call dbg_expect,\
   cc/x cc/y bb/x aa/x bb/y aa/y,\
   $(call <forAllItems>,.,out))


# help=open for inferred items
$(call dbg_expect,\
  aa/x,\
  $(findstring aa/x,$(subst \\,/,$(call <openRule>,$(call <matchOpen>,aa/x,$(call <forAllItems>,<openItem>))))))

AA.parent =
BB.parent =
CC.parent =


#----------------------------------------------------------------
# generators
#----------------------------------------------------------------

#### Base

G.parent = Gen
G.generate! = $(eval G.generated = $C:$I)
F.parent = G
F.generate! = 1
H.parent = G

stdgens = Copy F G Gen H Zip
$(call dbg_expect,$(stdgens),$(filter $(foreach v,_,$(<generators>)),$(stdgens)))

H = gx


definedFlags = $(sort $(foreach c,$(foreach C,$1,$(<chain>)),$(call <subfilter>,$c.flag-%,%,$(.VARIABLES))))

#### Options

_gf = $(call Options_override,,$(call Options_expand,$1,$2))

$(call dbg_expect,x noy,$(call _gf,  nox x y noy,  XY=x;y))
$(call dbg_expect,x noy,$(call _gf,  nox XY noy ,  XY=x;y))

$(call dbg_expect,b noa e nod,$(call _gf,a b noa DE nod,DE=d;e))

gf.parent = Options
gf.flags = a b $(call inherit)
gf.flagFilter = %
gf.flagAliases = BC=b;c DE=d;e
gf.flag-a = A
gf.flag-b = B
gf.flag-c = C
gf.flag-d = D
gf.flag-e = E
gf[F].flags = $(call inherit) nod

V.flags = $(subst _, ,$I)

$(call dbg_expect,B E,$(strip $(foreach v,noa_DE,$(call get,options,gf,F))))

all: ; @true

$(build)
$(call dbg_expect,H:gx,$(G.generated))
