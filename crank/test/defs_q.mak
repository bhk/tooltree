# unit tests for crank.min

include .config
include $(crank)/defs.min
include $(crank)/debug.min
$(if $(value dbg_expect),,$(error debug.min was not included))

#----------------------------------------------------------------

# reverse
$(call dbg_expect,a b c d,$(call <reverse>,d c b a))
$(call dbg_expect,a,$(call <reverse>,a))
$(call dbg_expect,,$(call <reverse>))


# double-check constants
$(call dbg_expect,	,$(\t))
$(call dbg_expect, ,$(\s))
$(call dbg_expect,\,$(\))

# <dirname>  (at this point it gives the directory of debug.min)
$(call dbg_expect,$(patsubst %/,%,$(crank)),$(<dirname>))

# <for>
$(call dbg_expect,aa:bb:cc,$(call <for>,x,a b c,$$x$$x,:))

# <defined>
$(call dbg_expect,dbg_flags,$(call <defined>,dbg_flags))
$(call dbg_expect,,$(call <defined>,*undef*))

# <uniq>
$(call dbg_expect,a b c,$(strip $(call <uniq>,a b a b c a)))

# <once>
onceX = $X
X := 1
$(call dbg_expect,1,$(call <once>,onceX))
X := 2
$(call dbg_expect,1,$(call <once>,onceX))

# <write>, <arg>
$(call dbg_expect,\,$(shell echo $(call <arg>,\)))
$(call dbg_expect,\\,$(shell echo $(call <arg>,\\)))
$(call dbg_expect,\\\\,$(shell echo $(call <arg>,\\\\)))
$(call dbg_expect,"",$(shell echo $(call <arg>,"")))
$(call dbg_expect,' ',$(shell echo $(call <arg>,' ')))

_in = )$(\)  $(\)$(\) $$$(\t)`"'$(\n) (#`
_out = 0000000 ) $(\) sp sp $(\) $(\) sp $$ ht ` " ' nl sp ( 0000017#`
$(call dbg_expect,$(_out),$(strip $(shell $(call <write>,$(_in)) | od -a)))

# <escape>
lft = (
rgt = )
testEscape = $(call dbg_expect,$1,$(call <eval>,EE = $(call <escape>,$1))$(EE))
$(call dbg_expect,a b,$(call <escape>,a b))
$(call testEscape,a)
$(call testEscape,  a$$b  )
$(call testEscape,$(rgt) a$(\n)$(\t)b$(lft) ! ^ - # \ \\ \# \\# )

# <toLower>, <toUpper>

$(call dbg_expect,\
   THE FIVE BOXING WIZARDS JUMP QUICKLY,\
   $(call <toUpper>,the five boxing wizards jump quickly))
$(call dbg_expect,\
   the five boxing wizards jump quickly,\
   $(call <toLower>,THE FIVE BOXING WIZARDS JUMP QUICKLY))

# <cleanPath>
cptest = $(call dbg_expect,$(strip $2),$(call <cleanPath>,$(strip $1)))

#               IN             OUT
#               --------       --------
$(call cptest,  ,                        )
$(call cptest,  a,             a         )
$(call cptest,  a/b/c,         a/b/c     )

$(call cptest,  .,             .         )
$(call cptest,  a/.,           a         )
$(call cptest,  ./.,           .         )
$(call cptest,  ./a,           a         )
$(call cptest,  a/./b,         a/b       )

$(call cptest,  ..,            ..        )
$(call cptest,  a/..,          .         )
$(call cptest,  a/b/..,        a         )
$(call cptest,  ../a,          ../a      )
$(call cptest,  ../..,         ../..     )
$(call cptest,  a/../b,        b         )
$(call cptest,  a/../../b,     ../b      )
$(call cptest,  a/b/../c,      a/c       )

$(call cptest,  ./..,          ..        )
$(call cptest,  ./.././..,     ../..     )

$(call cptest,  /,             /.        )
$(call cptest,  /a,            /a        )
$(call cptest,  /a/.,          /a        )
$(call cptest,  /./a,          /a        )
$(call cptest,  /a/./b,        /a/b      )
$(call cptest,  /a/../b,       /b        )
$(call cptest,  /a/../../b,    /../b     )
$(call cptest,  /../../b,      /../../b  )
$(call cptest,  /a/b/../../c,  /c        )
$(call cptest,  /.,            /.        )
$(call cptest,  /a/..,         /.        )

# UNC paths
$(call cptest,  //a/b/..,      //a       )
$(call cptest,  //a/..,        //.       )

# list of dirs
$(call cptest,  a b/.. c,      a . c     )


# <relpath>

$(call dbg_expect,.. .. c d,$(call <xrelpath>,A B a b,A B c d))
$(call dbg_expect,../../c/d,$(call <relpath>,/A/B/a/b,/A/B/c/d))
$(call dbg_expect,..,$(call <relpath>,a/b/c,a/b))
$(call dbg_expect,c,$(call <relpath>,a/b,a/b/c))
$(call dbg_expect,.,$(call <relpath>,a/b,a/b))
# traverse about current dir (assume this directory is called "test")
$(call dbg_expect,../../test/to,$(call <relpath>,../from/x,to))
$(call dbg_expect,.,$(call <relpath>,../from/x,../from/x))

# <searchPath>

$(call dbg_expect,../defs.min,$(call <searchPath>,defs.min,foo/ ./ ./../))
$(call dbg_expect,defs_q.mak,$(call <searchPath>,defs_q.mak,.. . foo))
spError = NOTFOUND:$1:$2
$(call dbg_expect,NOTFOUND:defs.min:foo,$(call <searchPath>,defs.min,foo,spError))

# <adjustPath>

#$(call dbg_expect,a/c a/b/x,$(call <adjustPath>,../c x,a/b/file))
#lastdir :=  $(dir $(lastword $(MAKEFILE_LIST)))
#$(call dbg_expect,$(lastdir)x/foo,$(call <adjustPath>,x/foo))

# <memoize>

# test <memovar>
$(call dbg_expect,\
  <@$$(subst $$(\s),^s,$$(subst $$(\t),^t,$$(subst ^,^1,$$a)^|$$(subst ^,^1,$$b)^|)),\
  $(call <memovar>,,$$a $$b))

# mt = function to memoize ('b' is *not* keyed)
mt = $1$2$a$b

# xmt = covenience for calling mt with 'a' and 'b' set
xmt = $(foreach a,$(or $3,?),$(foreach b,$(or $4,?),$(call mt,$1,$2)))

# memoized same as non-memoized
$(call dbg_expect,onetwoAB,$(call xmt,one,two,A,B))
$(call <memoize>,mt,$$1 $$2 $$a)
$(call dbg_expect,onetwoAB,$(call xmt,one,two,A,B))

# second call returns memoized value
$(call dbg_expect,onetwoAB,$(call xmt,one,two,A,Z))

# not memoized when context variable changes
$(call dbg_expect,onetwoaZ,$(call xmt,one,two,a,Z))

# nasty input and output characters
$(call dbg_expect,  one $(\c) = AB,$(call xmt,  one, $(\c) = ,A,B))
$(call dbg_expect, 1$(\t) 2 AB,$(call xmt, 1$(\t), 2 ,A,B))
$(call dbg_expect, 1$(\t) 2 -B,$(call xmt, 1$(\t), 2 ,-,B))

# <words> & <packWords>

$(call dbg_expect,$(words $(<wqI>)),$(words $(<wqI>)))

text = "!\#$$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~ _ . +
#"
$(call dbg_expect,$(text),$(call <words>,$(call <packWords>,$(text))))


################################
# object system
################################

# call $1 in context of C ($2) and I ($3)
x. = $(call <call>,$1,$2,.,$3)
x& = $(call <call>,$1,$2,&,$3)
x&! = $(call <call>,$1,$2,&!,$3)

ClassA.x = ABC
ClassB.parent = ClassA ClassD
ClassC.parent = ClassB
ClassC[i].x = XYZ

##### inheritance chain

ClassC[item].parent = ClassB[$I] ClassD

#  ClassC[item];ClassB[item];ClassB;ClassA;ClassD;,\
$(call dbg_expect,\
  ClassC[item];ClassB;ClassA;ClassD;,\
  $(foreach C,ClassC,$(foreach I,item,$(<&&>))))


#### "&" and "."

$(call dbg_expect,ClassC[i].x,$(call x&,ClassC,i,x))
$(call dbg_expect,ClassA.x,$(strip $(call x&,ClassC,-undef,x)))
$(call dbg_expect,ABC,$(call x.,ClassC,-undef,x))

### Class.*

wca.* = A
wcb.parent = wca
wcb.* = $(call inherit):B
wcc.parent = wcb

$(call dbg_expect,,$(call x&,wcc,inst,prop))
$(call dbg_expect,wcb.*,$(call x&!,wcb,inst,prop))
$(call dbg_expect,wcb.*,$(call x&!,wcc,inst,prop))
$(call dbg_expect,A,$(call get,prop,wca,inst))
$(call dbg_expect,A:B,$(call get,prop,wcb,inst))
$(call dbg_expect,A:B,$(call get,prop,wcc,inst))

#### get, get*

ClassA.m = $I:$C:$(call .,x)

$(call dbg_expect,i:ClassC:XYZ,$(call get,m,ClassC,i))

ClassC = i j
$(call dbg_expect,i:ClassC:XYZ j:ClassC:ABC,$(call get*,m,ClassC))

#### super

A.parent = Root
B.parent = A

A.in = X
B.in = $(inherit) Y

# delegate from class to superclass
B[item].in = $(call inherit)
$(call dbg_expect,X Y,$(call get,in,B,nosuchitem))

# delegate from item to class
B[itemA].in = A $(call inherit)
$(call dbg_expect,A X Y,$(call get,in,B,itemA))

# "current property" should be set by '.' as well as get
B.xin = $(call .,in)
$(call dbg_expect,X Y,$(call get,xin,B,nosuchitem))

# new properties queried *within* '+' should search entire chain
A.in = $(call .,z)
B.z = Z
$(call dbg_expect,Z Y,$(call get,xin,B,nosuchitem))

# $1 inheritsFrom $2 ?
$(call dbg_expect,Root,$(call <inheritsFrom>,B,Root))

#----------------------------------------------------------------
# Variants

V.prop = @V $(call inherit)
V-a.prop = @V-a $(call inherit)
V-p.prop = @V-p $(call inherit)
V-b.parent = V-p
V-b.prop = @V-b $(call inherit)
V[a_b].prop = @V[a_b] $(call inherit)


$(call dbg_expect,\
  V[a_b];V-a;V-b;V-p;V;,\
  $(foreach C,V,$(foreach I,a_b,$(<v&&>))))

$(call dbg_expect,\
  @V[a_b] @V-a @V-b @V-p @V ,\
  $(call <vget>,prop,a_b))


#----------------------------------------------------------------
all: ; @true
