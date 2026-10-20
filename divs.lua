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
    -- No list topsep inside the columns: it only lands at the top of the
    -- first column, which would then start lower than the second.
    local out = {raw("\\begin{multicols}{2}\\raggedright\\setlist{topsep=0pt,partopsep=0pt}")}
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

-- A section heading sits in the left margin and takes the first line of
-- whatever follows. Inside two columns that pushes only the first column
-- down, so when columns follow a section heading directly, the heading
-- gets an empty line of its own and both columns start below it.
-- (Pandoc runs this after Div above, so it sees the multicols opening.)
function Pandoc(doc)
  if not (FORMAT:match("latex") or FORMAT:match("pdf")) then
    return nil
  end
  local blocks = doc.blocks
  for i = #blocks - 1, 1, -1 do
    local b, n = blocks[i], blocks[i + 1]
    if b.t == "Header" and b.level == 1 and n.t == "RawBlock"
       and n.text:find("\\begin{multicols}", 1, true) == 1 then
      blocks:insert(i + 1, raw("\\leavevmode\\par"))
    end
  end
  return doc
end
