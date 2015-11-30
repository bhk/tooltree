include .config
include $(crank)/crank.min

# ** exporting env vars

EchoVar.parent = Phony
EchoVar += foo
EchoVar.command = env | grep EVAR=
EchoVar.exports = EVAR
  EchoVar[foo].EVAR = $(\s)$(EVAR)AB #
EchoVar.in =

$(build)
