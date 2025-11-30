-- AppleScript that uses arguments
on run argv
	if (count of argv) > 0 then
		return item 1 of argv
	else
		return "No arguments provided"
	end if
end run
