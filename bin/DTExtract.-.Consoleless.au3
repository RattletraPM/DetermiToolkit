#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.15.0 (Beta)
 Author:         RattletraPM

 Script Function:
	Extracts the STRG chunk from data.win, then extracts the strings from that
	chunk. If everything went well, it will also save some metadata about
	data.win for later use.

	Part of DetermiToolkit (former UDTranslation Kit).

	This script has been commented in english so that other translators will be
	able to understand how it works and modify it to their own needs.

#ce ----------------------------------------------------------------------------

#include <FileConstants.au3>
#include <AutoItConstants.au3>
#include <Crypt.au3>
;#include <Console.au3>			;Shaggi's Console.au3 UDF. You can find it in DetermiToolkit's "include" folder.
;#include <ConsoleEX.au3>		;UDF for additional misc console functions, some written by my and some randomly found online. Again, you can find it in the "include" folder.

Opt("TrayIconHide",1)	;This script doesn't need the tray icon at all

$currentdir=""

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
Const $strgdir=$currentdir&"res\STRG\"		;Where to extract the strings & metadata INI
$offset=""	;Current offset read from data.win

;Load the data.win directory from the INI config file
$datawin=IniRead($inifiledir,"DetermiToolkitCFG","datawin","ERROR")

;We need to check if $strgdir exists and, if it doesn't, create it
$dirempty=DirGetSize($strgdir,1)
If @error<>0 Then	;In case there has been an error, it probably means there's a file called "STRG" in the directory
	FileDelete($strgdir)	;We need to delete it, or else the script will crash
	DirCreate($strgdir)
EndIf

;~ ;If res/STRG isn't empty, let the user choose what to do
;~ $dirempty=DirGetSize($strgdir,1)
;~ If @error<>0 Then	;In case there has been an error, it probably means there's a file called "STRG" in the directory
;~ 	FileDelete($strgdir)	;We need to delete it, or else the script will crash
;~ 	DirCreate($strgdir)
;~ 	$dirempty=DirGetSize($strgdir,1)	;We need to get the dir size again or the script will crash
;~ EndIf
;~ If $dirempty[1]<>0 Then
;~ 	_Cmsg($CONMSG_WARNING,"WARNING: The STRG folder isn't empty. Its files will be overwritten!"&@CRLF)
;~ 	Cout("Press [y] to proceed or any other key to abort."&@CRLF)
;~ 	If Getch()<>"y" Then
;~ 		_Cmsg($CONMSG_ERROR,"Operation aborted by the user."&@CRLF)
;~ 		PauseExit()
;~ 	EndIf
;~ EndIf

;First off, we check data.win's existance
If FileExists($datawin)==0 Then
	Exit 10
EndIf
$datahandle=FileOpen($datawin,$FO_BINARY)
$databin=FileRead($datahandle)
;I'm usings StringInStr instead of FileSetPos and FileRead as I don't know at the moment which is faster in binary mode. I'll run tests later
;on to see which is faster and modify this script if needed
$strgstart=StringInStr($databin,"53545247") ;53545247 = STRG in HEX
If $strgstart==0 Then	;If $strgstart is equal to 0, it means that STRG hasn't been found in data.win
	Exit 11
EndIf

;A little explaination for the variable below: we first have to subtract 3 to $strgstart as reading files in binary mode in AutoIt
;automatically adds "0x" at the start of the file (as the file is returned in hexadecimal representation) and StringInStr is a 1-based
;function, so StringInStr starts counting from 1 instead of 0. After doing so, we'll have to divide the result by 2 as we want to know
;at which BYTE the STRG chunk starts (and if we leave it the way it is, we'd have known its offset in BITS instead). Lastly, we take the
;result and convert it as an integer (AutoIt treats all non-integer numbers passed to Hex() as doubles, so we have to use Int() before
;using Hex() to avoid unexpected results), then we convert it in HEX for convenience.
;---------------------------------------------------------------------------------------------------------------------
;Again, using Int() before Hex() is VERY IMPORTANT - don't remove it or you most probably will get unexpected results!
;---------------------------------------------------------------------------------------------------------------------
$strgstarthex=String(Hex(Int(($strgstart-3)/2)))
;We also need to find the last subchunk in data.win (AUDO) as the game won't boot if there is data that belongs to FORM but doesn't belong
;to any subchunk. We can work around this by increasing AUDO's size and putting our relocated strings in there, without altering anything
;else in it (this way the individual audio files won't become corrupted)
$audostart=StringInStr($databin,"4155444F") ;4155444F = AUDO in HEX
If $audostart==0 Then	;If $audostart is equal to 0, it means that STRG hasn't been found in data.win
	Exit 12
EndIf
FileClose($datahandle)
$audostarthex=String(Hex(Int(($audostart-3)/2)))
$databin=StringTrimLeft($databin,$strgstart+7)
;Now we read some data from STRG and save it for later use
Const $strgsize=ByteReverse(StringLeft($databin,8))	;Size of STRG
$databin=StringTrimLeft($databin,8)
Const $strgnum=ByteReverse(StringLeft($databin,8))	;Number of strings in STRG
WriteMetadata()
WriteWarningFile()
$databin=StringTrimLeft($databin,8)

;Value to subtract to the string's offset, as we have deleted a lot of bytes from data.win. Will be used during the string extraction process
;and it's declared out of the Do...Until loop to speed up the process
Const $offsetfix=$strgstart+20

$i=0
Do
	$percent=Round(($i/Dec($strgnum))*100)												;Percentage to show on the console
	$offset=ByteReverse(StringMid($databin,(8*$i)+1,8))									;Read the string's offset from the offset list
	$strlen=ByteReverse(StringMid($databin,(Dec($offset)*2)-$offsetfix,8))			;Read the string's lenght
	;Then read the acutal string. Notice how we need to add 10 to $strlen (10 bits=5 bytes) as the 4 bytes representing the string's
	;lenght and the terminator byte (00) aren't included in $strlen's count. If you don't understand any of this, read my tutorial:
	;in it, I explain in depth how strings are stored in data.win
	$readstr=StringMid($databin,(Dec($offset)*2)-$offsetfix,(Dec($strlen)*2)+10)
	$stringfile=FileOpen($strgdir&$i&".bin",BitOr($FO_BINARY,$FO_OVERWRITE))
	FileWrite($stringfile,Binary("0x"&$readstr))
	FileClose($stringfile)
	;First, set the cursor position on the console to the right coords
	_ReduceMemory()
	$i+=1
Until $i==Dec($strgnum)
Exit 0

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

Func WriteWarningFile()	;This function writes a file telling the user to not delete anything inside STRG
	Local Const $warningfile=FileOpen($strgdir&"DON'T DELETE ANYTHING.txt",$FO_OVERWRITE)
	FileWrite($warningfile, "If you delete stuff from this directory you will only get trouble when reinserting the strings inside data.win or creating a standalone patcher (either a 'String count mismatch' error or 'Metadata missing' error). So feel free to edit any bin file in here but please don't delete anything. It's for your own good!")
	FileClose($warningfile)
EndFunc

Func WriteMetadata()	;This function writes metadata for data.win in an INI file
	Local Const $metafile = $strgdir&"metadata.ini"
	IniWrite($metafile, "Don't edit stuff inside this INI", "Pretty please", "Or you might get errors when reinserting strings / creating a standalone patcher")
	IniWrite($metafile, "Metadata", "OrigMD5", _Crypt_HashFile($datawin, $CALG_MD5))
	IniWrite($metafile, "Metadata", "StrgStartHex", $strgstarthex)
	IniWrite($metafile, "Metadata", "StrgNum", $strgnum)
	IniWrite($metafile, "Metadata", "AudoStartHex", $audostarthex)
EndFunc

; Reduce memory usage
; Author wOuter ( mostly )
Func _ReduceMemory($i_PID = -1)

    If $i_PID <> -1 Then
        Local $ai_Handle = DllCall("kernel32.dll", 'int', 'OpenProcess', 'int', 0x1f0fff, 'int', False, 'int', $i_PID)
        Local $ai_Return = DllCall("psapi.dll", 'int', 'EmptyWorkingSet', 'long', $ai_Handle[0])
        DllCall('kernel32.dll', 'int', 'CloseHandle', 'int', $ai_Handle[0])
    Else
        Local $ai_Return = DllCall("psapi.dll", 'int', 'EmptyWorkingSet', 'long', -1)
    EndIf

    Return $ai_Return[0]
EndFunc;==> _ReduceMemory()

;~ Func PauseExit()	;Displays "Press any key to exit", waits for user input, then exits
;~ 	Cout("Press any key to exit.")
;~ 	Cpause()
;~ 	Exit
;~ EndFunc