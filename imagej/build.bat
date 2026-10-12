@echo off
REM Build Vessel_Permeability-1.0.0.jar without Maven (Windows).
REM Usage:  build.bat C:\path\to\Fiji.app\jars\ij-1.54f.jar
if "%~1"=="" (
  echo Pass the path to ij.jar, e.g. C:\Fiji.app\jars\ij-1.54f.jar
  exit /b 1
)
cd /d "%~dp0"
if exist build rmdir /s /q build
mkdir build\classes
javac -encoding UTF-8 --release 8 -Xlint:-options -cp "%~1" -d build\classes src\main\java\vesselpermeability\*.java || exit /b 1
copy src\main\resources\plugins.config build\classes\ >nul
pushd build\classes
jar cf ..\Vessel_Permeability-1.0.0.jar .
popd
echo Built build\Vessel_Permeability-1.0.0.jar - copy it into Fiji.app\plugins\
