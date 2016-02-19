#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.15.0 (Beta)
 Author:         RattletraPM

 Script Function:
	Joins the various binary strings stored in res/STRG togheter, then injects
	them inside data.win by relocating them at the end of the file, correcting
	the pointer table and FORM's size

	Part of DetermiToolkit (former UDTranslation Kit).

	This script has been commented in english so that other translators will be
	able to understand how it works and modify it to their own needs.

#ce ----------------------------------------------------------------------------

#include <File.au3>
#include <FileConstants.au3>
#include <AutoItConstants.au3>
#include <Crypt.au3>
#include <Console.au3>			;Shaggi's Console.au3 UDF. You can find it in UDT-ITA DevKit's "include" folder.
#include <ConsoleEX.au3>		;UDF for additional misc console functions, some written by my and some randomly found online. Again, you can find it in the "include" folder.

Opt("TrayIconHide",1)	;This script doesn't need the tray icon at all

$currentdir=""

Cout("- DetermiToolkit v0.4b by RattletraPM -"&@CRLF)
Cout("String injection engine build 20160216"&@CRLF&@CRLF)
;Cout("This build of DetermiToolkit is private and may contain bugs (see TODO)"&@CRLF&"Do not redistribute!"&@CRLF&@CRLF)
Cout("This build of DetermiToolkit is unstable and may contain bugs (see TODO)"&@CRLF&@CRLF)

;We already know that this tool will be placed inside a directory called "bin" and we need to get lots of stuff in the directory up one level,
;so what we need to do is to get @ScriptDir and remove the last occurrence of "bin" from it. As an added bonus, the resulting string will always include a trailing backslash!
$currentdir=StringReplace(@ScriptDir,"bin","",-1)

;~ ;If the extr folder is empty or doesn't exist, there's no sense to go on - return a critical error
;~ $dirempty=DirGetSize($currentdir&"extr",1)
;~ If @error<>0 Then
;~ 	_Cmsg($CONMSG_CRITICAL,"CRITICAL: The extr folder doesn't exist! Run UDTPrep first."&@CRLF)
;~ 	PauseExit()
;~ EndIf
;~ If $dirempty[1]==0 Then
;~ 	_Cmsg($CONMSG_CRITICAL,"CRITICAL: The extr folder is empty! Run UDTPrep first."&@CRLF)
;~ 	PauseExit()
;~ EndIf

;Variables & Constants
Const $inifiledir=$currentdir&"res\DTConfig.ini"	;DetermiToolkit INI config file
Const $datawin=IniRead($inifiledir,"DetermiToolkitCFG","datawin","ERROR")		;Expected path of data.win file
Const $strgdir=$currentdir&"res\STRG\"			;Where to read the strings & metadata INI
Const $metafile=$strgdir&"metadata.ini"			;Location of metadata.ini file
Const $tmpstrgfile=$strgdir&"tmpstrg"			;Temporary file with the rebuilt STRG chunk inside
$strgstarthex=-1								;Hexadecimal pointer of the STRG chunk
$audostarthex=-1								;Hexadecimal pointer of the AUDO chunk
$strgnum=-1										;Number of strings inside data.win

;~ ;Same thing applies for res/STRG - return a critical error if empty
;~ $dirempty=DirGetSize($strgdir,1)
;~ If @error<>0 Then
;~ 	_Cmsg($CONMSG_CRITICAL,"CRITICAL: The res\STRG folder doesn't exist!"&@CRLF)
;~ 	PauseExit()
;~ EndIf
;~ If $dirempty[1]==0 Then
;~ 	_Cmsg($CONMSG_CRITICAL,"CRITICAL: The res\STRG folder is empty!"&@CRLF)
;~ 	PauseExit()
;~ EndIf

;First off, we check data.win's existance
If FileExists($datawin)==0 Then
	_Cmsg($CONMSG_CRITICAL,"CRITICAL: data.win doesn't exist in the given directory!"&@CRLF)
	PauseExit()
EndIf
;Now, we check if metadata.ini exists too. The script can run without it but it might be dangerous, so we'll ask the user what to do
$iniexists=FileExists($metafile)
If $iniexists==0 Then
	_Cmsg($CONMSG_WARNING,"WARNING: metadata.ini doesn't exist."&@CRLF&"The patch can still be applied, but it might lead to unexpected results."&@CRLF&@CRLF&"Are you sure you want to continue?"&@CRLF)
	Cout("Press [y] to proceed or any other key to abort."&@CRLF)
	If Getch()<>"y" Then
		_Cmsg($CONMSG_ERROR,"Operation aborted by the user."&@CRLF)
		PauseExit()
	EndIf
	STRGReadMetadata()
Else
	;In case data.win's MD5 is the same as the one stored in metadata.ini, we can just use the metadata we stored earlier
	If String(_Crypt_HashFile($datawin, $CALG_MD5))==IniRead($metafile, "Metadata", "OrigMD5", -1) Then
		_Cmsg($CONMSG_SUCCESS, "MD5 hash match! The script will load data from metadata.ini"&@CRLF)
		$strgstarthex=IniRead($metafile, "Metadata", "StrgStartHex", -1)
		$audostarthex=IniRead($metafile, "Metadata", "AudoStartHex", -1)
		$strgnum=IniRead($metafile, "Metadata", "StrgNum", -1)
		InjectStrings()
	EndIf
	_Cmsg($CONMSG_WARNING, "WARNING: MD5 hash mismatch, trying to read data from data.win"&@CRLF)
	STRGReadMetadata()
EndIf

Func STRGReadMetadata()
	_Cmsg($CONMSG_INFO, "Searching for the STRG chunk in data.win..."&@CRLF)
	Local $datahandle=FileOpen($datawin,$FO_BINARY)
	Local $databin=FileRead($datahandle)
	Local $strgstart=StringInStr($databin,"53545247") ;53545247 = STRG in HEX
		If $strgstart==0 Then	;If $strgstart is equal to 0, it means that STRG hasn't been found in data.win
		_Cmsg($CONMSG_CRITICAL,"CRITICAL: STRG doesn't exist in data.win!"&@CRLF)
		PauseExit()
	EndIf
	$strgstarthex=String(Hex(Int(($strgstart-3)/2)))
	_Cmsg($CONMSG_SUCCESS,"STRG found at offset "&$strgstarthex&" (HEX)."&@CRLF)
	_Cmsg($CONMSG_INFO, "Searching for the AUDO chunk in data.win..."&@CRLF)
	$audostart=StringInStr($databin,"4155444F") ;4155444F = AUDO in HEX
	If $audostart==0 Then	;If $audostart is equal to 0, it means that STRG hasn't been found in data.win
		_Cmsg($CONMSG_CRITICAL,"CRITICAL: AUDO doesn't exist in data.win!"&@CRLF)
		PauseExit()
	EndIf
	FileClose($datahandle)
	$audostarthex=String(Hex(Int(($audostart-3)/2)))
	_Cmsg($CONMSG_SUCCESS,"AUDO found at offset "&$audostarthex&" (HEX)."&@CRLF)
	_Cmsg($CONMSG_INFO, "Trimming unneeded data..."&@CRLF)	;In order to speed up later tasks, we'll trim everything before STRG
	$databin=StringTrimLeft($databin,$strgstart+15)
	$strgnum=ByteReverse(StringLeft($databin,8))
	InjectStrings()
EndFunc

Func InjectStrings()
	Local $i=0,$cmd

	_Cmsg($CONMSG_INFO,"STRG Pointer: "&$strgstarthex&" AUDO Pointer: "&$audostarthex&" Number of strings: "&$strgnum&@CRLF)
	Local $binarray=_FileListToArray($strgdir,"*.bin",$FLTA_FILES)	;List all bin files in res\STRG
	;If the number of files isn't equal to the number of strings, then bad things may happen. Ask the user what to do
	If String(Hex($binarray[0],8))<>$strgnum Then
		_Cmsg($CONMSG_ERROR,"ERROR: String count mismatch."&@CRLF&@CRLF&"The patch may be corrupt or intended for a different version of the game."&@CRLF&"Applying the patch will most likely corrupt your game."&@CRLF&@CRLF&"Are you sure you want to continue?"&@CRLF)
		Cout("Press [y] to proceed or any other key to abort."&@CRLF)
		If Getch()<>"y" Then
			_Cmsg($CONMSG_ERROR,"Operation aborted by the user."&@CRLF)
			PauseExit()
		EndIf
	EndIf
	_Cmsg($CONMSG_INFO, "Merging strings..."&@CRLF)
	;First of all, we'll check if a previous tmpstrg file exists and, in order to avoid merging the strings inside it, we'll delete it
	If FileExists($tmpstrgfile) Then
		FileDelete($tmpstrgfile)
	EndIf
	;Now, we'll have to merge the strings in a single file.
	;We'll merge 500 strings at a time due to CMD's limitations and we'll be using the (rushed and horrendous) BuildCmd() function below
	;to help us doing so.
	Do
		If FileExists($tmpstrgfile) Then
			RunWait("cmd /c copy /b tmpstrg+"&BuildCmd($binarray,$i)&"=tmpstrg",$strgdir,@SW_HIDE,$STDOUT_CHILD)
		Else
			RunWait("cmd /c copy /b "&BuildCmd($binarray,$i)&"=tmpstrg",$strgdir,@SW_HIDE,$STDOUT_CHILD)
		EndIf
		$i+=500
	Until $i>=$binarray[0]
	;Now that we have all the strings in one file, we can proceed with the real string injection. Howerer, in order to reduce memory usage
	;we'll first fix FORM's lenght and to do so we need to know the size of data.win and the size of the previously generated tmpstrg
	_Cmsg($CONMSG_INFO, "Fixing FORM's lenght..."&@CRLF)
	Local $tmpstrgsize=FileGetSize($tmpstrgfile)
	Local $datawinsize=FileGetSize($datawin)
	Local $hdatawin=FileOpen($datawin,BitOr($FO_BINARY,$FO_APPEND))
	FileSetPos($hdatawin,4,$FILE_BEGIN)
	;We have to subtract 8 bytes as FORM's magic bytes an lenght bytes aren't included in the total byte count
	FileWrite($hdatawin,Binary("0x"&ByteReverse(String(Hex(($datawinsize+$tmpstrgsize)-8,8)))))
	;It's time to edit STRG's offset table. Again, we'll do this before appending the strings to reduce memory usage
	_Cmsg($CONMSG_INFO, "Editing STRG's offset table..."&@CRLF)
	$i=0									;Reset $i's value, as it has already been used in this function
	Local $totsize=0						;Total size of the strings so far - needed to calculate the offsets properly
	Local $strgtable=Dec($strgstarthex)+12	;STRG's offset table offset
	Do
		Local $binsize=FileGetSize($strgdir&$i&".bin")
		FileSetPos($hdatawin,$strgtable+($i*4),$FILE_BEGIN)
		FileWrite($hdatawin,Binary("0x"&ByteReverse(String(Hex($datawinsize+$totsize,8)))))
		$totsize=$totsize+$binsize
		$i+=1
	Until $i==$binarray[0]
	;In order for the game to work properly all data needs to be part of a subchunk (if it's included in FORM but doesn't belong
	;to any subchunk, the game crashes as it thinks it wasn't loaded properly into memory). Given that AUDO is the last chunk, the best
	;thing to do is to increase AUDO's size so that the relocated strings will be part of it - but we won't touch anything else so they
	;will effectively be ignored by AUDO
	Local $audostartdec=Dec($audostarthex)
	_Cmsg($CONMSG_INFO, "Editing AUDO's size..."&@CRLF)
	FileSetPos($hdatawin,$audostartdec+4,$FILE_BEGIN)
	;We don't need to read AUDO's size from data.bin - it's the last chunk so we can calculate it easily
	ByteReverse(String(Hex((($datawinsize+$totsize)-$audostartdec)-8,8)))
	FileWrite($hdatawin,Binary("0x"&ByteReverse(String(Hex((($datawinsize+$totsize)-$audostartdec)-8,8)))))
	FileClose($hdatawin)
	;Finally, we'll append the strings using copy /b
	_Cmsg($CONMSG_INFO, "Appending edited strings to data.win..."&@CRLF)
	RunWait('cmd /c copy /b "'&$datawin&'"+"'&$strgdir&'tmpstrg"="'&$datawin&'"',@WorkingDir,@SW_HIDE,$STDOUT_CHILD)
	_Cmsg($CONMSG_SUCCESS, "All done!"&@CRLF)
	PauseExit()
EndFunc

Func ByteReverse($instr)	;Function used to reverse bytes of a given string
	Local $ret, $i
	Local $len = StringLen($instr)/2

	If StringIsFloat($len) == 1 Then		;If $instr's lenght can't be divided by 2, it means that something went wrong
		Return -1
	EndIf
	Do
		$ret=$ret&StringRight($instr,2)		;Get the last byte and place it at the end of the newly formed string...
		$instr=StringTrimRight($instr,2)	;...delete that byte from the original string...
		$i+=1								;...increase the index value by one...
	Until $i==$len							;...and repeat for each byte in $instr
	Return $ret
EndFunc

;This function may suck, but hey - I wanted to code something that works and I was in a rush, so here it is.
;If anyone's kind enough to rewrite it in a better way, you're free to do so.
Func BuildCmd($arr,$i)
	;Yeah, I know - I probably needed two variables at worst. But hey - if you have any complaints, read the comment above
	Local $cmd,$lim,$icmd

	;In case there are less than 500 files left we need to adjust the $lim variable to how many files are left. If not, set it to 500.
	If $i+500>=$arr[0] Then
		$lim=$arr[0]-$i
	Else
		$lim=500
	EndIf
	Do
		;Notice how I'm using $i&".bin" to get the file names instead of $arr[$i]. That's not because I'm an idiot, but it's for a very
		;important reason: AutoIt doesn't any kind of sorting option to _FileListToArray()and may return the list in a non-sequential order.
		;Howerer, we need to reinsert the strings sequentially, so the only real way to be sure is to use $arr[0] to get the total number
		;of files and then use another variable to list them sequentially.
		;---------------------------------------------------------------------------
		;TL;DR - DON'T USE $arr[i], it might merge strings in a non-sequential order
		;---------------------------------------------------------------------------
		$cmd=$cmd&$i&".bin+"
		$i+=1
		$icmd+=1
	Until $icmd==$lim
	$cmd=StringTrimRight($cmd,1)	;Again, there's probably a beter way to do it, but we need to remove that + at the end.

	Return $cmd
EndFunc

Func PauseExit()	;Displays "Press any key to exit", waits for user input, then exits
	Cout("Press any key to exit.")
	Cpause()
	Exit
EndFunc