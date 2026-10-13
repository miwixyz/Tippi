-- Ein Fall: Text in neues TextEdit-Dokument, Cursor ans Ende, letzte Zeichen tippen,
-- warten, einmal ⇥, Dokumenttext zurückgeben. Bricht ab, wenn TextEdit nicht vorne ist.
-- NUR mit NSDocumentSaveNewDocumentsToCloud = false (global) laufen lassen — sonst legt
-- TextEdit jedes Dokument trotz „saving no" in iCloud ab (13.10.: 85 Dateien).
on run argv
	set ctxText to read (POSIX file (item 1 of argv)) as «class utf8»
	set getippt to item 2 of argv
	tell application "TextEdit"
		activate
		set d to make new document
		set text of d to ctxText
	end tell
	delay 0.8
	tell application "System Events"
		set vorn to name of first process whose frontmost is true
		if vorn is not "TextEdit" then return "ABBRUCH: vorne ist " & vorn
		key code 125 using command down -- Cursor ans Dokumentende
		delay 0.2
		repeat with c in characters of getippt
			set vorn to name of first process whose frontmost is true
			if vorn is not "TextEdit" then return "ABBRUCH: Fokus bei " & vorn
			keystroke (c as text)
			delay 0.08
		end repeat
	end tell
	delay 2.5
	tell application "System Events"
		set vorn to name of first process whose frontmost is true
		if vorn is not "TextEdit" then return "ABBRUCH vor Tab: vorne ist " & vorn
		key code 48 -- ⇥
	end tell
	delay 0.8
	tell application "TextEdit"
		set ergebnis to text of front document
		close front document saving no
	end tell
	return ergebnis
end run
