# The default target runs unit tests.  Demo targets (anim_demo, etc.)
# create HTML files that can be used to visually inspect behavior.

Alias(default).in = JSTest@jsTests
jsTests = $(wildcard *_q.js)

# make 'Demo(X)'  --> create HTML from X_demo.js  & open it in a browser

Demo.inherit = Run
Demo.in = JSToHTML({inherit}_demo.js)
Demo.exec = open {<}

include-deps = $(build-js-exports)/build-js.mk
include ../build/tooltree.mk
