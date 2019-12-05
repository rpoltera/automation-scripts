echo Home automation. data download batch file

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  :: Location of your downloader
set downloader=D:\downloader\downloader.exe

  :: Destination folder for zip files
set directory=d:\guide

"C:\Program Files\7-Zip\7z.exe" a "G:\guide backup\%DATE:~7,2%.%DATE:~4,2%.%DATE:~-4% %TIME:~0,2%.%TIME:~3,2%.%TIME:~-5% Backup".7z  D:\guide\full\

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
set url=https://xxxxxxxxxxxxx.com 
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: 1. delete old files after backup compleated
del "D:\guide\*.* 
del "D:\guide\full\*.* 

:: 2. File "full.xml.gz" (our inventory, part 1 of 1)
"%downloader%" -download %url%full.xml.gz "%directory%\full.xml.gz"

"C:\Program Files\7-Zip\7z.exe" e D:\guide\*.xml.gz -od:\guide\full\



echo Batch file completed
