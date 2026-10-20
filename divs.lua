-- Maps the two custom divs used in cv.qmd to LaTeX environments.
-- HTML output ignores this filter and uses the classes in styles.css.

local function raw(s)
  return pandoc.RawBlock("latex", s)
end

function Div(el)
  if not (FORMAT:match("latex") or FORMAT:match("pdf")) then
    return nil
  end

  if el.classes:includes("columns-two") then
    local out = {raw("\\begin{multicols}{2}\\raggedright")}
    for _, b in ipairs(el.content) do table.insert(out, b) end
    table.insert(out, raw("\\end{multicols}"))
    return out
  end

  if el.classes:includes("note") then
    local out = {raw("\\begin{cvnote}")}
    for _, b in ipairs(el.content) do table.insert(out, b) end
    table.insert(out, raw("\\end{cvnote}"))
    return out
  end

  return nil
end
