#!/bin/sh
# 清理重复/旧的 Finder 扩展注册，只保留“应用程序”里的正式副本。
# 用法：sh scripts/reset_finder_extension.sh
set -e

APP="/Applications/RightClickAssistant.app"
EXT_ID="devplaceholder.JW2H7X4Z.RightClickAssistant.FinderExtension"

echo "1) 退出正在运行的副本…"
pkill -f 'RightClickAssistant.app/Contents/MacOS/RightClickAssistant' 2>/dev/null || true
pkill -f 'RightClickAssistant.app/Contents/MacOS/RightClickAssistant' 2>/dev/null || true
pkill -f 'FinderExtension.appex/Contents/MacOS/FinderExtension' 2>/dev/null || true

echo "2) 移除不在 /Applications 的旧注册（构建目录等）…"
pluginkit -m -A -v -p com.apple.FinderSync \
  | grep -iE 'rightclick|右键|RightClickAssistant' \
  | awk -F'\t' '{print $NF}' \
  | while read -r path; do
      case "$path" in
        /Applications/*) ;;
        *) echo "   移除: $path"; pluginkit -r "$path" 2>/dev/null || true ;;
      esac
    done

echo "3) 重新注册“应用程序”里的副本…"
pluginkit -a "$APP/Contents/PlugIns/FinderExtension.appex"
pluginkit -e use -i "$EXT_ID" 2>/dev/null || true

echo "4) 当前注册状态："
pluginkit -m -A -v -p com.apple.FinderSync | grep -iE 'rightclick|右键' || echo "   （无）"

echo "5) 重启 Finder 以重新加载扩展…"
killall Finder 2>/dev/null || true

echo "6) 重新打开“RightClickAssistant”…"
open "$APP"

echo "完成。若系统设置仍显示旧条目，请关闭并重新打开“系统设置”。"
