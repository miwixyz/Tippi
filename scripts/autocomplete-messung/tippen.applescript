-- Tippt einen Satz in ein neues TextEdit-Dokument und liest Tippis Vorschlagskapsel.
-- Bricht ab, sobald TextEdit nicht vorne ist (sonst landen Tasten woanders).
on run argv
	set satz to item 1 of argv
	tell application "TextEdit"
		activate
		make new document
	end tell
	delay 1.0
	tell application "System Events"
		set vorn to name of first process whose frontmost is true
		if vorn is not "TextEdit" then return "ABBRUCH: vorne ist " & vorn
		repeat with c in characters of satz
			set vorn to name of first process whose frontmost is true
			if vorn is not "TextEdit" then return "ABBRUCH: Fokus bei " & vorn
			keystroke (c as text)
			delay 0.06
		end repeat
	end tell
	delay 2.5
	-- Ganzen Vorschlag mit ⇧⇥ übernehmen und Ergebnis aus dem Dokument lesen
	tell application "System Events"
		set vorn to name of first process whose frontmost is true
		if vorn is not "TextEdit" then return "ABBRUCH vor ⇧⇥: vorne ist " & vorn
		key code 48 using shift down
	end tell
	delay 0.8
	tell application "TextEdit" to set ergebnis to text of front document
	set gefunden to ""
	tell application "System Events"
		tell process "Tippi"
			repeat with w in windows
				try
					repeat with e in (entire contents of w)
						try
							if role of e is "AXStaticText" then set gefunden to gefunden & "[" & (value of e as text) & "]"
						end try
					end repeat
				end try
			end repeat
		end tell
	end tell
	-- Dokument leeren und schließen, ohne zu speichern
	tell application "TextEdit"
		close front document saving no
	end tell
	return "Dokument: «" & ergebnis & "»"
end run
