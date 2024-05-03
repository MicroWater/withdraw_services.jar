#!/bin/bash

sudo timedatectl set-timezone Asia/Shanghai
sudo apt-get remove -y firefox zstd
sudo apt-get install python3 aria2

URL="$1"              # 移植包下载地址   
GITHUB_ENV="$2"       # 输出环境变量
GITHUB_WORKSPACE="$3" # 工作目录

device=houji # 设备代号

Red='\033[1;31m'    # 粗体红色
Yellow='\033[1;33m' # 粗体黄色
Blue='\033[1;34m'   # 粗体蓝色
Green='\033[1;32m'  # 粗体绿色

port_os_version=$(echo ${URL} | cut -d"/" -f4)                   
port_version=$(echo ${port_os_version} | sed 's/OS1/V816/g')     
port_zip_name=$(echo ${URL} | cut -d"/" -f5)                   
vendor_os_version=$(echo ${URL} | cut -d"/" -f4)          
vendor_version=$(echo ${vendor_os_version} | sed 's/OS1/V816/g')
vendor_zip_name=$(echo ${URL} | cut -d"/" -f5)     

android_version=$(echo ${URL} | cut -d"_" -f5 | cut -d"." -f1) 
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)   

sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools
magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
ksud="$GITHUB_WORKSPACE"/tools/ksud
a7z="$GITHUB_WORKSPACE"/tools/7zzs
zstd="$GITHUB_WORKSPACE"/tools/zstd
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
apktool_jar="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"

Start_Time() {
  Start_s=$(date +%s)
  Start_ns=$(date +%N)
}

End_Time() {
  local End_s End_ns time_s time_ns
  End_s=$(date +%s)
  End_ns=$(date +%N)
  time_s=$((10#$End_s - 10#$Start_s))
  time_ns=$((10#$End_ns - 10#$Start_ns))
  if ((time_ns < 0)); then
    ((time_s--))
    ((time_ns += 1000000000))
  fi

  local ns ms sec min hour
  ns=$((time_ns % 1000000))
  ms=$((time_ns / 1000000))
  sec=$((time_s % 60))
  min=$((time_s / 60 % 60))
  hour=$((time_s / 3600))

  if ((hour > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$hour小时$min分$sec秒$ms毫秒"
  elif ((min > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$sec秒$ms毫秒"
  elif ((sec > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$sec秒$ms毫秒"
  elif ((ms > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒"
  else
    echo -e "${Green}- 本次$1用时: ${Blue}$ns纳秒"
  fi
}

### 系统包下载
echo -e "${Red}- 开始下载系统包"
echo -e "${Yellow}- 开始下载移植包"
Start_Time
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$URL"
### 系统包下载结束

### 解包
echo -e "${Red}- 开始解压系统包"
mkdir -p "$GITHUB_WORKSPACE"/Third_Party
mkdir -p "$GITHUB_WORKSPACE"/"${device}"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip

echo -e "${Yellow}- 开始解压移植包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/$port_zip_name -r -o"$GITHUB_WORKSPACE"/Third_Party >/dev/null
End_Time 解压移植包
sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
cd "$GITHUB_WORKSPACE"/images
echo -e "${Red}- 开始解移植包payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/images/ -i "$GITHUB_WORKSPACE"/Third_Party/payload.bin -X system -T0
echo -e "${Red}- 开始分解移植包image"
for i in system; do
  echo -e "${Yellow}- 正在分解移植包: $i"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/images/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/Third_Party
### 解包结束


### 功能修复
echo -e "${Red}- 开始修改并提取services.jar"
Start_Time
# 移除 Android 签名校验
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
echo -e "${Red}- 移除 Android 签名校验"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
cd "$GITHUB_WORKSPACE"/apk
sudo $apktool_jar d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read -r i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "${Yellow}- ${i} 修改成功"
done
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $apktool_jar b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar

