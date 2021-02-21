[CmdletBinding()]
param(
    [IO.FileInfo[]]$WidgetPaths,
    [IO.DirectoryInfo]$targetPath = "C:\Program Files (x86)\Steam\steamapps\common\Zero-K\LuaUI\Widgets"
)
mkdir $targetPath -force
Copy-Item *.lua $targetPath