-- smark_msc:  Message Sequence Chart macro for Smark
--
-- Macro argument = MSCGen string

local mscgen = require "mscgen"

local MSC = {}  -- parent class for ".msc" macro nodes

function MSC:render2D(gc)
   local function warn(pos, ...)
      self._source:warn(pos, ...)
   end
   return mscgen.render( mscgen.parse(self.text, warn), gc)
end

return MSC
