include .config

TEST: ; @true

#--------------------------------
#
# Sample package structure. Here we defined `package` properties
# for the packages so no actual `Package` files are required.
#

override Project = a b?x
override Variants = a b


Package.dir = .

define Package[a].package
  # a?a -> a?b
  Project = $(if $(filter a,$v),a?b)
  make = echo "V=$V"
  v = $q
endef


define Package[b].package
  Project = a?a
  make = echo "V=$V"
  v = y
endef

include $(crank)/project.mak

#--------------------------------

include $(crank)/debug.min

# <mapKey>
# <mapValue>
$(call dbg_expect,a,$(call <mapKey>,a=b=c))
$(call dbg_expect,,$(call <mapKey>,=b=c))
$(call dbg_expect,b=c,$(call <mapValue>,=b=c))
$(call dbg_expect,b=c,$(call <mapValue>,a=b=c))

# <allEQ>

$(call dbg_expect,1,$(call <allEQ>, a a a a))
$(call dbg_expect,,$(call <allEQ>, a a b a))
$(call dbg_expect,1,$(call <allEQ>, ))


# test `.` and `get`
cls.x = $I
cls.y = y
cls[a].x = A$IA$(call .,y)
cls = a b
$(call dbg_expect,AaAy b,$(call get*,x,cls))
$(call dbg_expect,b,$(call get,x,cls,b))


dpvNorm = $(foreach d,$1,$(foreach p,$2,$(foreach v,$3,$(dpv.norm))))

# normalize
$(call dbg_expect,x=p?v,$(call dpvNorm,x=p?v,P,V))
$(call dbg_expect,x=p?V,$(call dpvNorm,x=p?,P,V))
$(call dbg_expect,x=p?V,$(call dpvNorm,x=p,P,V))
$(call dbg_expect,x=P?v,$(call dpvNorm,x=?v,P,V))
$(call dbg_expect,x=P?V,$(call dpvNorm,x=?,P,V))
$(call dbg_expect,p=p?v,$(call dpvNorm,p?v,P,V))
$(call dbg_expect,p=p?V,$(call dpvNorm,p?,P,V))
$(call dbg_expect,p=p?V,$(call dpvNorm,p,P,V))
$(call dbg_expect,P=P?v,$(call dpvNorm,?v,P,V))
$(call dbg_expect,P=P?V,$(call dpvNorm,?,P,V))

# get fields
$(call dbg_expect,x,$(foreach d,x=p?v,$(d.var)))
$(call dbg_expect,p,$(foreach d,x=p?v,$(d.pkg)))
$(call dbg_expect,v,$(foreach d,x=p?v,$(d.q)))


# visit...

$(call <do>,<visit>)

# top-level builds
$(call dbg_expect,a b,$(foreach p,all,$(p.V)))

$(call dbg_expect,a all b,$(sort $(Package)))
$(call dbg_expect,a@a a@b all@a all@b b@y,$(sort $(Build)))

$(call dbg_expect,y,$(foreach p,b,$(p.V)))
$(call dbg_expect,a b,$(foreach p,a,$(p.V)))


#----------------------------------------------------------------
# graph
#----------------------------------------------------------------

$(call dbg_expect, |   |      ,$(call graph.prefix,a:b:c c:d -,b,V))
$(call dbg_expect, +-> +->    ,$(call graph.prefix,a:b:c b:c:d -,b,H))

testMap = $(subst :, ,$(call <assoc>,$1,top=a:b:c a=b:d))

$(call dbg_expect,b:c - b:d,$(call graph.slots,a:b:c a,a,testMap))
$(call dbg_expect,b:c,$(call graph.slots,x:b:c x,x,testMap))

$(call dbg_expect,top a d b c ,$(call graph.trav,top,testMap))

define OUT

 top
 |
 +-> a
 |   |
 |   +-> d
 |   |
 +-> +-> b
 |
 +-> c

endef

testFmt = $1

stripTrailingSpaces = \
  $(if $(findstring $(\s)$(\n),$1),$(call $0,$(subst $(\s)$(\n),$(\n),$1)),$1)

$(call dbg_expect,$(OUT),$(call stripTrailingSpaces,$(call graph.text,top,testMap,testFmt)))

# Detect cycle in graph

testMap = $(subst :, ,$(call <assoc>,$1,top=a:b:c a=b:d b=c c=a))
$(call dbg_expect,top c a b CYCLE:top:c:a:b:c d ,$(call graph.trav,top,testMap))


#$(info DESCRIPTION)
#$(call <dump>)
