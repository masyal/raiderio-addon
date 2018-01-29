@echo off
setlocal enabledelayedexpansion

set toc_interface=70300
set toc_author=Vladinator ^(Voidzone-Ravencrest^) and Aspyr ^(Aspyrael-Skullcrusher^)
set toc_addon=RaiderIO

for %%r in (
	"US	Americas"
	"EU	Europe"
	"KR	Korea"
	"TW	Taiwan"
) do (
	set r=%%r
	set r1=!r:~1,2!
	set r2=!r:~4,-1!

	for %%f in (
		"A	Alliance"
		"H	Horde"
	) do (
		set f=%%f
		set f1=!f:~1,1!
		set f2=!f:~3,-1!

		set d=.\RaiderIO_DB_!r1!_!f1!
		set f=.\!d!\!d!.toc

		set lr=!r1!
		set lf=!f2!
		call :LoCase lr
		call :LoCase lf

		rmdir /s /q "!d!"
		mkdir "!d!"

		echo ## Interface: !toc_interface!>"!f!"
		echo ## Title: Raider.IO Mythic Plus ^(!r2! - !f2!^)>>"!f!"
		echo ## Notes: Raider.IO Mythic Plus Scores DB for !r2! - !f2!. Updated nightly.>>"!f!"
		echo ## Author: !toc_author!>>"!f!"
		echo ## Dependencies: !toc_addon!>>"!f!"
		echo ## DefaultState: enabled>>"!f!"
		echo ## X-Region: !r2!>>"!f!"
		echo ## X-Faction: !f2!>>"!f!"
		echo ## X-Website: https:^/^/raider.io>>"!f!"
		echo ../!toc_addon!/db/db_!lr!_!lf!_characters.lua>>"!f!"
		echo ../!toc_addon!/db/db_!lr!_!lf!_lookup.lua>>"!f!"
	)
)
goto end

REM http://www.robvanderwoude.com/battech_convertcase.php
:LoCase
:: Subroutine to convert a variable VALUE to all lower case.
:: The argument for this subroutine is the variable NAME.
FOR %%i IN ("A=a" "B=b" "C=c" "D=d" "E=e" "F=f" "G=g" "H=h" "I=i" "J=j" "K=k" "L=l" "M=m" "N=n" "O=o" "P=p" "Q=q" "R=r" "S=s" "T=t" "U=u" "V=v" "W=w" "X=x" "Y=y" "Z=z") DO CALL SET "%1=%%%1:%%~i%%"
GOTO:EOF

:end
pause
