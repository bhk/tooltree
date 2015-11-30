-- ".example" macro:  markup side-by-side with results

return function(node, doc)
   local E = require("smarklib").E
   return E.table {
      E.tr {
         E.th { "Input", align="center", width="50%" },
         E.th { "Output", align="center", width="50%" },
      },
      E.tr {
         E.td {
            class="pre", style="white-space: pre;", _whitespace = true,
            node.text,
         },
         E.td {
            doc.parse(node._source),
         }
      },
   }
end

