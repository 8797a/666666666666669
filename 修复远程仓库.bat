@echo off
echo 正在修复远程仓库配置...
cd /d "%~dp0"
git remote remove origin
echo 远程仓库配置已清除！
echo 现在可以在 GitHub Desktop 重新发布了。
pause
