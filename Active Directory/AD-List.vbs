		'V--V   AD-Parse.vbs     V--V'
		'V--V VampyreMan Studios V--V'
		'V--V  Author : Khristos V--V'
		'SIMPLE SCRIPT TO PARSE ACTIVE'
		'DIRECTORY ON THE TQ NETWORK &'
		'FIND INACTIVE USERS, DISABLE '
		'THEM AND MOVE THEM TO THE OU '
		'FOR DISABLED ACCOUNTS AND SET'
		'A DESCRIPTION OF WHEN IT WAS '
		' DISABLED AND HOW MANY DAYS  '
		'IT WAS INACTIVE FOR DISABLED '


	''DEFINES CONSTANTS EQUAL TO WINDOWS HEX CODES FOR USER FLAGS''
Const ADS_AUTH = &H0001
Const ADS_NO_AUTH = &H0010
Const ADS_UF_SCRIPT = &H0001
Const ADS_UF_LOCKOUT = &H0010
Const ADS_UF_DISABLE = &H0002
Const ADS_SERVER_BIND = &H0200
Const ADS_UF_ACCOUNTDISABLE = &H0002
Const ADS_UF_PASSWD_NOTREQD = &H0020
Const ADS_UF_PASSWORD_EXPIRED = &H800000
Const ADS_UF_DONT_EXPIRE_PASSWD = &H10000
Const ADS_UF_SMARTCARD_REQUIRED = &H40000

On Error Resume Next

	''DEFINE VARIABLES FOR USE IN SCRIPT''
Dim objDSP, objOU, objAD, objDIS, objDISch, objFSO
Dim strDis, strDN, strServ, crawlDN, strName, strPass, useCNT

useCNT = 0

	''ASSIGNS VALUES TO RESPECTIVE VARIABLES, WHEN THE VARIABLES ARE USED IN''
	''THE SCRIPT, THEY REPRESENT THE VALUES ASSIGNED HERE IN QUOTATION MARKS''
strDis = "ou=_DISABLED"
strDN = "dc=tq,dc=mnf-wiraq,dc=usmc,dc=mil"
strServ = "tqn02ns.tq.mnf-wiraq.usmc.mil"


	''THESE LINES ARE COMMENTED OUT AND NOT USED IN THE SCRIPT.''
	''THE INTENTION OF THESE COMMANDS WAS TO PROVIDE AN AUTHENTICATION''
	''MEANS. HOWEVER, THE SCRIPT COULD NOT AUTHENTICATE PROPERLY ON''
	''OUR DOMAIN (POSSIBLY A DIFFERENT AUTHENTICATION METHOD/HASH)''
	''AND THE SCRIPT INHERITS THE PERMISSIONS OF THE USER THAT EXECUTES IT.''
'WScript.Echo "Please Enter Username:"
'strName = WScript.StdIn.ReadLine
'set objPass = CreateObject("ScriptPW.Password")
'WScript.Echo "Please Enter Password For: " & strName
'strPass = objPass.GetPassword
'set objPass = nothing

	''THE NEXT FIVE COMMANDS CREATE THE LDAP OBJECT, CONNECT TO THE TQ DOMAIN,''
	''AND CREATE A DATED 'DISABLED' OU TO MOVE ACCOUNTS THAT ARE DISABLED INTO.''
	''THE THREE COMMANDS THAT ARE COMMENTED OUT ARE THE COMMANDS THAT CREATE''
	''THE DATED 'DISABLED' OU. I HAD THEM COMMENTED OUT DURING THE TESTING OF''
	''THE SCRIPT SO AS NOT TO CHANGE ANYTHING IN ACTIVE DIRECTORY. THESE WILL''
	''NEED TO BE UNCOMMENTED FOR FINAL IMPLEMENTATION OF THE SCRIPT.''
Set objDSP = GetObject("LDAP:")
Set objOU = objDSP.OpenDSObject("LDAP://ou=TQ," & strDN, vbnullstring, vbnullstring, ADS_SERVER_BIND)
'Set objDIS = GetObject("LDAP://" & strDis & "," & strDN)
'Set objDISch = objDIS.Create("organizationalUnit", "ou=DISABLED " & Year(Now) & Month(Now) & Day(Now)) 
'objDISch.SetInfo

	''THESE TWO COMMANDS CREATE THE VBSCRIPT FILE SYSTEM AND A DATED''
	''LOGFILE IN THE WINDOWS FOLDER. THIS LOGFILE IS USED TO RECORD EACH''
	''DISABLED ACCOUNT AND A RELATIVE LOCATION OF WHERE THE ACCOUNT''
	''WAS IN ACTIVE DIRECTORY BEFORE BEING DISABLED BY THE SCRIPT.''
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objLog = objFSO.CreateTextFile("C:\Windows\AD-Parse.log" & Year(Now) & Month(Now) & Day(Now))

	''THIS WILL CALL 'ENUMUSERS' SUB-ROUTINE, ONCE THAT HAS COMPLETED''
	''THE NEXT COMMAND WILL CALL 'SCRCLEAN' SUB-ROUTINE TO FINALIZE SCRIPT''
Call enumUsers(objOU)
Call scrClean

	''THE 'ENUMUSERS' SUB-ROUTINE TAKES THE ACTIVE DIRECTORY PATH PROVIDED''
	''AND COLLECTS ALL OBJECTS WHICH ARE CHILDS OF THAT PATH. THIS''
	''ROUTINE IS RECURSIVE, CALLING ITSELF FOR EACH ACTIVE DIRECTORY''
	''OBJECT UNTIL IT REACHES THE FINAL OBJECT IN ACTIVE DIRECTORY''
Sub enumUsers(pathAD)

		''DEFINE A 'BOOLEAN' VARIABLE FOR CONDITIONAL LOGIC''
		''AND AN ARRAY OF 'TAGS' TO IDENTIFY ACCOUNTS, TYPES''
		''OF ACCOUNTS, OR OU CONTAINING ACCOUNTS THAT SHOULD''
		''NOT BE DISABLED OR MOVED FROM THEIR LOCATION''
	Dim blnCHK
	Dim chkArray(4)
	chkArray(0) = "SMB"
	chkArray(1) = "SYSCON"
	chkArray(2) = "SERVICE"
	chkArray(3) = "SHAREPOINT"

	On Error Resume Next

		''FOR EACH OBJECT CONTAINED IN THE AD PATH PROVIDED''
	For Each objAD In pathAD

			''CREATE A CONDITION BASED ON THE TYPE OF OBJECT''
		Select Case objAD.Class

				''IF THE OBJECT IS A USER OBJECT''
			Case "user"

					''IF THE ACCOUNT IS NOT DISABLED ALREADY''
				If objAD.AccountDisabled = False then

						''SET THE 'BOOLEAN' CONDITION TO TRUE''
					blnCHK = "TRUE"

						''FOR EACH ITEM IN OUR ARRAY OF 'DO NOT DISABLE' LIST''
					For x = 0 to 3

							''CHECK THE OBJECT FOR THE 'TAG' CORRESPONDING TO ITEM NUMBER''
						If instr(1, lcase(objAD.name), lcase(chkArray(x))) Then

								''IF A 'TAG' IS FOUND, SET THE 'BOOLEAN' CONDITION TO FALSE''
							blnCHK = "FALSE"
						End If
					Next

						''A FINAL CHECK FOR DESCRIPTIONS THAT MARK THE OBJECT AS A 'DO NOT DISABLE' OBJECT''
					If instr(1, lcase(objAD.description), "do not disable") Then
						blnCHK = "FALSE"
					ElseIf instr(1, lcase(objAD.description), "don't disable") Then
						blnCHK = "FALSE"
					End If

						''IF THE 'BOOLEAN' CONDITION IS STILL TRUE''
					If blnCHK = "TRUE" Then
						useCNT = useCNT + 1

							''GET THE LAST LOGON TIME FOR THE ACCOUNT''
						Set objLogon = objAD.get("lastlogontimestamp")

							''THE FOLLOWING CONVERT THE TIMESTAMP TO A LEGIBLE DATE''
						intLogon = objLogon.highpart * (2 ^ 32) + objLogon.lowpart
						intLogon = intLogon / (60 * 10000000)
						intLogon = intLogon / 1440
						intLogon = intLogon + # 1 / 1 / 1601 #

							''THIS WAS JUST A TESTING COMMAND''
							'' CAN BE LEFT COMMENTED OUT OR IT CAN BE REMOVED''
						'MsgBox "Approximate last logon for: " & objAD.name & " is " & vbnewline & vbtab & intLogon

							''IF THE LAST LOGON IS ANYTHING OTHER THAN '1/1/1601', CHECK HOW LONG AGO''
						If intLogon <> "1/1/1601" Then
							usrDD = DateDiff("d", intLogon, Now)

								''IF LAST LOGON IS 30 DAYS OR MORE''
							If usrDD >= 30 Then

									''WRITE THE ACCOUNT NAME AND DAYS OF INACTIVITY
									'' TO DATED LOGFILE PREVIOUSLY CREATED''
								objLog.WriteLine vbtab & objAD.name & vbtab & usrDD & " DAYS"

									''THESE WERE COMMENTED OUT FOR TESTING OF THE SCRIPT''
									''UNCOMMENT THESE FOR FINAL IMPLEMENTATION OF SCRIPT''
									''THE FOLLOWING FOUR COMMANDS DISABLE THE ACCOUNT, THEN''
									''ADD A DATED DESCRIPTION OF WHEN IT WAS DISABLED''
									''AND DAYS OF INACTIVITY, AND MOVE THE ACCOUNT''
									''TO THE PREVIOUSLY CREATED 'DISABLED' OU''
								'objUser.accountdisabled = True
								'objUser.put "description", "***DISABLED " & Now & " : HASN'T LOGGED ON IN " & usrDD & " DAYS***"
								'objUser.setinfo
								'objDIS.movehere "LDAP://" & user & "," & crawlDN & strDN, vbnullstring
							End If
						End If
					End If
				End If

				''IF THE OBJECT IS AN ORGANIZATIONAL UNIT OBJECT''
			Case "organizationalUnit"

					''IF IT IS ANY OU OTHER THAN THE '_DISBALED' OU''
				If objAD.name <> "OU=_DISABLED" Then

						''SET THE 'BOOLEAN' CONDITION TO TRUE''
					blnCHK = "TRUE"

						''FOR EACH ITEM IN OUR 'DO NOT DISABLE' LIST''
					For x = 0 to 3

							''CHECK FOR THE 'TAG' CORRESPONDING TO ITEM NUMBER''
						If instr(1, lcase(objAD.name), lcase(chkArray(x))) Then

								''IF A 'TAG' IS FOUND, SET 'BOOLEAN' CONDITION TO FALSE''
							blnCHK = "FALSE"
						End If
					Next

						''IF THE 'BOOLEAN' CONDITION IS STILL TRUE''
					If blnCHK = "TRUE" Then

							''RECORD THE OU IN THE PREVIOUSLY CREATED LOGFILE''
						objLog.WriteLine objAD.Name

							''CALL 'ENUMUSERS' PROVIDING THE PATH OF THAT OU''
							''THIS WILL RECURSIVELY PERFOM THE PREVIOUS COMMANDS''
							''FOR ALL QUALIFYING OBJECTS IN ACTIVE DIRECTORY''
						Call enumUsers(objAD)
					End If
				End If
		End Select
	Next
End Sub

	''THE 'SCRCLEAN' SUB-ROUTINE. THIS WILL NOTIFY THE USER THAT''
	''THE SCRIPT IS COMPLETE AND WHERE THEY CAN VIEW THE LOG OF''
	''DISABLED ACCOUNTS. THEN IT WILL PERFORM 'CLEAN-UP' OF SCRIPT''
Sub scrClean()
	objLog.writeline useCNT
	MsgBox "Script Complete. View C:\Windows\AD-Parse.log" & Year(Now) & Month(Now) & Day(Now) & " for listing of disabled users.", vbokonly, "AD-Parse by: Khristos"
	Set objLogon = Nothing
	Set objUser = Nothing
	Set objAD = Nothing
	Set pathAD = Nothing
	Set objFSO = Nothing
	Set objOU = Nothing
	Set objDIS = Nothing
	Set objDSP = Nothing
	WScript.Quit
End Sub