--!strict
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

-- 950 -> "950", 1234 -> "1.2K", 3500000 -> "3.5M"
function Format.number(n: number): string
	local negative = n < 0
	n = math.abs(math.floor(n))
	local tier = 1
	while n >= 1000 and tier < #SUFFIXES do
		n /= 1000
		tier += 1
	end
	local text
	if tier == 1 then
		text = tostring(n)
	elseif n >= 100 then
		text = string.format("%d%s", math.floor(n), SUFFIXES[tier])
	else
		text = string.format("%.1f", math.floor(n * 10) / 10):gsub("%.0$", "") .. SUFFIXES[tier]
	end
	return (if negative then "-" else "") .. text
end

function Format.money(n: number): string
	return "$" .. Format.number(n)
end

return Format
