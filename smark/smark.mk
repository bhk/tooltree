# Minion-style builder for building HTML using Smark

# SmarkDoc(TEXTFILE): Generate an HTML file from Smark markup.
#
SmarkDoc.inherit    = _SmarkDoc
_SmarkDoc.inherit    = Exec
_SmarkDoc.outExt     = .html
_SmarkDoc.command    = {exportPrefix} {smarkExe} -o {@} {flags} -- {^}
_SmarkDoc.css        =
_SmarkDoc.depsFile   = {@}.dep
_SmarkDoc.flags      = $(patsubst %,--no-default-css --css='%',{css}) {warnFlags} --deps={depsFile}
_SmarkDoc.warnFlags  = --error
_SmarkDoc.smarkExe  := $(dir $(lastword $(MAKEFILE_LIST)))smark
_SmarkDoc.up         = {smarkExe}
_SmarkDoc.exports    = SMARK_PATH
_SmarkDoc.SMARK_PATH = ./?.lua
