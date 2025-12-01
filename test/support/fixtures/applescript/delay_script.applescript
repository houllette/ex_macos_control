-- AppleScript with delay for timeout testing
on run argv
	set delaySeconds to 2
	if (count of argv) > 0 then
		set delaySeconds to item 1 of argv as integer
	end if
	delay delaySeconds
	return "Completed after " & delaySeconds & " seconds"
end run
