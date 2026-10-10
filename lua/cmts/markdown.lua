-- We gotta deal with markdown separately to avoid treating it as indented text

local M = {}
local attached = setmetatable({}, { __mode = "k" })

local function range6(buf, sr, sc, er, ec)
	return { sr, sc, vim.api.nvim_buf_get_offset(buf, sr) + sc, er, ec, vim.api.nvim_buf_get_offset(buf, er) + ec }
end

local function dedent(buf, range)
	local sr, sc, er, ec = unpack(range)
	local lines = vim.api.nvim_buf_get_lines(buf, sr, er + 1, false)
	local indent
	for i, line in ipairs(lines) do
		local row = sr + i - 1
		local text = line:sub(row == sr and sc + 1 or 1, row == er and ec or #line)
		if text:find("[^ \t]") then
			local width = #text:match("^[ \t]*")
			indent = math.min(indent or width, width)
		end
	end
	if not indent or indent == 0 then
		return { range6(buf, sr, sc, er, ec) }
	end
	local ranges = {}
	for i, line in ipairs(lines) do
		local row = sr + i - 1
		local start = row == sr and sc or 0
		local finish = row == er and ec or #line
		local text = line:sub(start + 1, finish)
		start = start + math.min(indent, #text:match("^[ \t]*"))
		if row < er then
			ranges[#ranges + 1] = range6(buf, row, start, row + 1, 0)
		elseif start < ec then
			ranges[#ranges + 1] = range6(buf, row, start, row, ec)
		end
	end
	return ranges
end

local function update(tree, buf, queries)
	local markdown = tree:children().markdown
	local query = queries[tree:lang()]
	if markdown and query then
		local annotations = {}
		for _, syntax_tree in pairs(tree:trees()) do
			for _, _, metadata in query:iter_matches(syntax_tree:root(), buf) do
				if metadata["injection.language"] == "markdown" then
					for id, name in ipairs(query.captures) do
						if name == "injection.content" and metadata[id] then
							annotations[#annotations + 1] = metadata[id].range
						end
					end
				end
			end
		end
		if #annotations > 0 then
			local regions = {}
			-- Keep unrelated Markdown injections. Replace ranges inside our annotated strings.
			for _, region in pairs(markdown:included_regions()) do
				local remaining = {}
				for _, range in ipairs(region) do
					local annotated = false
					for _, annotation in ipairs(annotations) do
						local outer = range6(buf, unpack(annotation))
						if range[3] >= outer[3] and range[6] <= outer[6] then
							annotated = true
							break
						end
					end
					if not annotated then
						remaining[#remaining + 1] = range
					end
				end
				if #remaining > 0 then
					regions[#regions + 1] = remaining
				end
			end
			for _, annotation in ipairs(annotations) do
				local ranges = dedent(buf, annotation)
				if #ranges > 0 then
					regions[#regions + 1] = ranges
				end
			end
			if not vim.deep_equal(markdown:included_regions(), regions) then
				markdown:set_included_regions(regions)
				markdown:parse(true)
			end
		end
	end
	for _, child in pairs(tree:children()) do
		update(child, buf, queries)
	end
end

function M.attach(buf, queries)
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok or not parser or attached[parser] then
		return
	end
	attached[parser] = true
	local pending, running, detached = false, false, false
	local function schedule()
		if pending or running or detached then
			return
		end
		pending = true
		vim.schedule(function()
			pending = false
			if detached or not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			running = true
			-- Native injection discovery resets the ranges. Repair them after it finishes.
			parser:parse(true)
			update(parser, buf, queries)
			running = false
		end)
	end
	parser:register_cbs({
		on_changedtree = schedule,
		on_detach = function()
			detached = true
		end,
	}, true)
	schedule()
end

return M
