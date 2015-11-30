-- default <style> contents for Smark documents -*-CSS-*-

return [=[
table {
   border-collapse: collapse;
   border-width: 1px;
   border-spacing: 1px;
   border-color: transparent;
   margin: 16px 0;
   width: 100%;
}
th {
   background-color: #bbb; color: white;
}
td, th {
   border-style: solid;
   border-color: black;
   border-width: 1px;
   padding: 0 6px;
}
td p:first-child, th p:first-child {
   margin-top: 3px;
}
td p:last-child, th p:last-child {
   margin-bottom: 3px;
}

.smarkdoc {
  margin-left: 42px; margin-right: 42px;
  font-size: 13px;
  font-family: 'Lucida Grande', Geneva, Helvetica, Arial, sans-serif;
}

h1, h2, h3 { color: #3c4c6c; }
h1 {
  text-align: center;
  font-size: 200%;
/*    margin-left: -30px; */
  clear: both;
}
h2 {
  font-size: 160%;
  margin: 32px -40px 24px -42px;
  padding: 3px 24px 8px;
  border-bottom: 2px solid #5088c5;
  clear: both;
}
h3 {
  font-size: 130%;
  margin: 20px -4px 10px;
  padding: 4px;
  clear: both;
}
h4 {
  font-size: 110%;
  margin: 2em 0 1em;
}

pre {
  font-size: 90%;
  background-color: #f0f0f4; padding: 6px; border: 1px solid #d0d0ee;
  font-family: "Courier New", "Lucida Console", "Monaco", monospace;
}

.pre {
  font-size: 90%;
  padding: 6px;
  background-color: #f0f0f4;
  font-family: "Courier New", "Lucida Console", "Monaco", monospace;
}

code {
  font-size: 90%;
  font-family: "Courier New", "Lucida Console", "Monaco", monospace;
}

h3 code {
  font-size: 100%;
}

p {
  margin: 0.8em 0;
}
ul, ol {
  margin: 1em 0 1em 3em; padding: 0;
}
div.indent {
  margin: 0 3em;
}

a[href] {
  text-decoration: none;
  color: #2020b0;
}
a[href]:hover {
  border-bottom: 1px dotted #2030d0;
}

/* Smark Users Guide */

.codebox {
  padding: 0 1px;  margin-right:1px;
  border:1px solid #d0d0ee;
  background-color: #f0f0f4;
  font-weight: bold;
  font-family: "Courier New", "Lucida Console", "Monaco", monospace;
}

/* ================ Smark-specific classes ================ */

.indent {
  margin: 0 3em;
}

/*
|| Floats affect text flow but not block boundaries, so graphics in a DIV
|| would overlap floats if not for "clear: both"
*/
.diagram {
  margin: 18px 0;
  clear: both;
}

/* ASCII Art */

.art {
  margin-right: auto; margin-left: auto; /* center */
  font-family: Arial, Verdana, "Lucida Console", Monaco, monospace;
  font-weight: bold;
}
.art * {
   border-color: #543;
}
.art .dline, .art .drect {
   border-style: dotted;
}
.art .rect {
   -webkit-box-shadow: 0.2em 0.2em 0.3em rgba(0,0,0,0.3);
   -moz-box-shadow: 0.2em 0.2em 0.3em rgba(0,0,0,0.3);
   box-shadow: 0.2em 0.2em 0.2em #875;
   background-color: #f9faf4; /* #fafff4; #f8f8ec;  */
}
.art .nofx {
   background-color: #f9faf4;
}
.art .round {
   border-radius: 0.6em;
   -webkit-border-radius: 0.6em;
   -moz-border-radius: 0.6em;
}

/* .art .line {  -webkit-box-shadow: 0.1em 0.1em 0.2em rgba(0,0,0,0.3); } */

/* Sequence Charts */

.msc {
   font: 11px Verdana, Monaco, "Lucida Console";
   margin-left: auto; margin-right: auto;
   background-color: white;
   /* border: 1px solid #555; */  /* Useful for non-white pages */
}

/* Table of Contents */

.tocLevel {
  margin-left: 2em;
  font-weight: normal;
}
.tocLevel .tocLevel {
  font-size: 90%; /* ...of inherited font size */
  line-height: 150%; /* ...of font size */
}
.toc > .tocLevel {
  font-weight: bold;
  margin: 0.5em 0
}
.toc {
  column-count: 2; column-gap: 2em;
  -moz-column-count: 2; -moz-column-gap: 2em;
  -webkit-column-count: 2; -webkit-column-gap: 2em;
}

/* ordinary text content is in P elements */

td p:first-child, th p:first-child {
   margin-top: 3px;
}
td p:last-child, th p:last-child {
   margin-bottom: 3px;
}
li p:only-child {
  margin-top: 0;
  margin-bottom: 0;
}

/* ================ Print ================ */

@media print {

  @page {
    margin: 0.75in 0.75in;
    size: Letter;
    @bottom {
      content: counter(page);
      vertical-align: top;
      padding-top: 1em;
    }
  }
  h1 { text-align: center;
       margin: 3in 0 20px; }
  h2 { page-break-before: always; }
  h2 { string-set: section content() }
  .toc { margin: 3em -2em }
  .toc a::after {
     font-size: 10px;
     content: leader(' . ') "  " target-counter(attr(href), page);
  }
  table { page-break-inside: avoid; }
}
]=]
