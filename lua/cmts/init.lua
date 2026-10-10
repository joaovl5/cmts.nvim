local M = {}
local prepared = {}
local queries = {}

local function is_comment(kind)
	return kind == "comment" or kind:match("_comment$") ~= nil
end

local function is_string(kind)
	return kind == "string"
		or kind:match("_string$") ~= nil
		or kind:match("string_literal$") ~= nil
		or kind:match("string_expression$") ~= nil
		or kind == "str_lit"
end

local function annotation(node, source)
	while node do
		local previous = node:prev_named_sibling()
		if previous and is_comment(previous:type()) then
			local row = node:start()
			local end_row = previous:end_()
			if row > end_row + 1 then
				return
			end
			local text = vim.treesitter.get_node_text(previous, source)
			local lang = text:match("^%s*%p+%s*([%a][%w_+%-]*)%s*%p*%s*$")
			return lang and (vim.treesitter.language.get_lang(lang) or lang)
		end
		local parent = node:parent()
		if not parent or parent:start() ~= node:start() or is_string(parent:type()) then
			return
		end
		node = parent
	end
end

local function content_range(node, source)
	local first = node:child(0)
	local last = node:child(node:child_count() - 1)
	if first and last then
		if first:type():match("content") and last:type():match("content") then
			local sr, sc = first:start()
			local er, ec = last:end_()
			return { sr, sc, er, ec }
		end
		local opening = vim.treesitter.get_node_text(first, source)
		local closing = vim.treesitter.get_node_text(last, source)
		local opens = opening:match("^[%w]*[\"'`]+$") or opening:match("^%[=*%[$")
		local closes = closing:match("^[\"'`]+$") or closing:match("^%]=*%]$")
		if opens and closes and first:id() ~= last:id() then
			local sr, sc = first:end_()
			local er, ec = last:start()
			return { sr, sc, er, ec }
		end
	end
	local text = vim.treesitter.get_node_text(node, source)
	local prefix, quotes = text:match("^([%w]*)([\"'`]+)")
	if quotes and text:sub(-#quotes) == quotes and #text >= #prefix + 2 * #quotes then
		local sr, sc, er, ec = node:range()
		return { sr, sc + #prefix + #quotes, er, ec - #quotes }
	end
end

local function prepare(lang)
	if prepared[lang] then
		return
	end
	local ok, info = pcall(vim.treesitter.language.inspect, lang)
	if not ok then
		return
	end
	local strings, comments = {}, false
	for kind, named in pairs(info.symbols) do
		if named then
			comments = comments or is_comment(kind)
			if is_string(kind) then
				strings[#strings + 1] = "(" .. kind .. ")"
			end
		end
	end
	prepared[lang] = true
	if not comments or #strings == 0 then
		return
	end
	table.sort(strings)
	local text = "([\n"
		.. table.concat(strings, "\n")
		.. [[
] @injection.content
  (#cmts-inject! @injection.content)
  (#set! injection.include-children))
]]
	queries[lang] = vim.treesitter.query.parse(lang, text)
	vim.treesitter.query.set(lang, "injections", ";; extends\n" .. text)
end

function M.setup()
	if M._loaded then
		return
	end
	M._loaded = true
	vim.treesitter.query.add_directive("cmts-inject!", function(match, _, source, predicate, metadata)
		local capture = predicate[2]
		local node = match[capture][1]
		local lang = annotation(node, source)
		local range = lang and content_range(node, source)
		if range then
			metadata["injection.language"] = lang
			metadata[capture] = { range = range }
		end
	end, { force = true })
	for _, path in ipairs(vim.api.nvim_get_runtime_file("parser/*", true)) do
		prepare(vim.fn.fnamemodify(path, ":t:r"))
	end
	local group = vim.api.nvim_create_augroup("cmts", { clear = true })
	local function set_highlight()
		vim.api.nvim_set_hl(0, "@cmts.text", { default = true, link = "Normal" })
	end
	set_highlight()
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlight })
	local markdown = require("cmts.markdown")
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(event)
			local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
			if lang then
				prepare(lang)
				markdown.attach(event.buf, queries)
			end
		end,
	})
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			markdown.attach(buf, queries)
		end
	end
end

return M
