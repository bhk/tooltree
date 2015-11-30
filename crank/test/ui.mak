# Tests of command-line options
#   'make open'
include .config
include $(crank)/crank.min

Copy.open = echo 'opening $I'
Copy.ext = .txt

Copy += ui.mak copy.mak

# 'open=ui' would match Copy[ui.mak], but it matches Copy[copy.mak] more precisely
Copy[copy.mak].out = $(call v.,buildDir)/ui


$(build)
