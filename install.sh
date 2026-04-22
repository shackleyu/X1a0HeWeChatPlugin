#!/bin/bash
set -uo pipefail

X1A0HE_WECHAT_PLUGIN_INSTALLER="X1a0He WeChat Plugin Installer"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 请使用 sudo 执行本脚本"
  exit 1
fi

WECHAT_PATH="/Applications/WeChat.app"

if [ ! -d "$WECHAT_PATH" ]
then
  WECHAT_PATH="/Applications/微信.app"
  if [ ! -d "$WECHAT_PATH" ]
  then
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 未找到目标路径，请先到微信官网下载微信"
    exit 1
  fi
fi

if pgrep -xq WeChat; then
  echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 检测到微信正在运行，请先退出微信后重试"
  exit 1
fi

WECHAT_VERSION=$(defaults read "$WECHAT_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null)
if [ -z "$WECHAT_VERSION" ]; then
  echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 读取微信版本失败，继续安装"
else
  echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 当前微信版本为：$WECHAT_VERSION"
fi
APP_NAME="wechat.dylib"
WECHAT_APP_PATH="$WECHAT_PATH/Contents/Resources"

WECHAT_EXECUTABLE_PATH="${WECHAT_APP_PATH}/${APP_NAME}"
WECHAT_EXECUTABLE_ORIGINAL_PATH="${WECHAT_APP_PATH}/${APP_NAME}.original"

CURRENT_USER="${SUDO_USER:-$(stat -f "%Su" /dev/console)}"

# 判断是否存在备份文件
if [ -f "$WECHAT_EXECUTABLE_ORIGINAL_PATH" ]
then
  echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 检测到已安装过，是否重新安装?[y/n]"
  read -r REPLY
  if [ "$REPLY" = "Y" ] || [ "$REPLY" = "y" ]
  then
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 正在清除旧的插件配置..."
    PLIST_PATH="$HOME/Library/Containers/com.tencent.xinWeChat/Data/Library/Preferences/com.tencent.xinWeChat.plist"
    if [ -f "$PLIST_PATH" ]; then
      for key in $(sudo -u "$CURRENT_USER" defaults read com.tencent.xinWeChat | grep -o "X1a0HeWeChatPlugin_[^\"]*"); do
        sudo -u "$CURRENT_USER" defaults delete com.tencent.xinWeChat "$key"
      done
    fi
    rm -f "$WECHAT_EXECUTABLE_PATH"
    cp "$WECHAT_EXECUTABLE_ORIGINAL_PATH" "$WECHAT_EXECUTABLE_PATH"
    if [ $? -ne 0 ]; then
      echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 恢复原始文件失败，请检查权限或重试"
      exit 1
    fi
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 旧版本已清理完成，开始安装新版本..."
  else
    exit 0
  fi
else
  echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 检测到是首次安装，正在备份原始文件..."
  cp "$WECHAT_EXECUTABLE_PATH" "$WECHAT_EXECUTABLE_ORIGINAL_PATH"
  if [ $? -ne 0 ]; then
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 备份失败，请检查权限或重试"
    exit 1
  fi
fi

# 拷贝动态库到微信目录
echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 正在拷贝插件到微信目录..."
cp "$SCRIPT_DIR/X1a0HeWeChatPlugin.dylib" "$WECHAT_APP_PATH"
if [ $? -ne 0 ]; then
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 拷贝插件失败，请检查权限或重试"
    exit 1
fi

# 注入动态库
echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 正在注入插件..."
chmod +x "$SCRIPT_DIR/insert_dylib"
xattr -dr com.apple.quarantine "$SCRIPT_DIR/insert_dylib" 2>/dev/null || true
"$SCRIPT_DIR/insert_dylib" "$WECHAT_APP_PATH/X1a0HeWeChatPlugin.dylib" "$WECHAT_EXECUTABLE_PATH" "$WECHAT_EXECUTABLE_PATH"
if [ $? -ne 0 ]; then
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 注入插件失败"
    exit 1
fi

# 重新签名
echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 正在重新签名..."
sudo /usr/bin/codesign -f -s - --all-architectures --entitlements "$SCRIPT_DIR/entitlements.xml" "$WECHAT_EXECUTABLE_PATH"
if [ $? -ne 0 ]; then
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 重新签名失败"
    exit 1
fi

echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 正在对 MacOS/WeChat 重新签名..."
sudo /usr/bin/codesign -f -s - --all-architectures --entitlements "$SCRIPT_DIR/entitlements.xml" "$WECHAT_PATH/Contents/MacOS/WeChat"
if [ $? -ne 0 ]; then
    echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] MacOS/WeChat 重新签名失败"
    exit 1
fi

echo "[${X1A0HE_WECHAT_PLUGIN_INSTALLER}] 安装完成！"
