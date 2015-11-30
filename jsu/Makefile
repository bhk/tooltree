# External dependencies
include .config
include $(crank)/crank.min
include $(crank-js)/crank-js.min


JSTest += $(wildcard *_q.js)


# To run look-and-feel tests:  make open=xxx_demo
JSToHTML += $(wildcard *_demo.js)


# Wishlist
#
#  * Observables
#     - observable map (from PSArray -> PSArray)
#     - element constructor that accepts observable PSArray of elements
#     - network observable w/ deactivation
#
#  * DOM Utilities
#     - accept children as observable PSArray
#     - activate on construction / deactivate on removeElement


$(build)
