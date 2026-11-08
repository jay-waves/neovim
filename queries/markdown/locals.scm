; extends
; Expose Markdown headings to FzfLua treesitter's locals-based symbol picker.
(document) @local.scope

(atx_heading
  (inline) @local.definition.heading)

(setext_heading
  (paragraph) @local.definition.heading)
