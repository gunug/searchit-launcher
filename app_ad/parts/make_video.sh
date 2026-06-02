#!/bin/bash
set -e

# 시간순서 이미지 6장
IMGS=(
  "ChatGPT Image 2026년 6월 1일 오후 12_00_25.png"
  "ChatGPT Image 2026년 6월 1일 오후 12_02_29.png"
  "ChatGPT Image 2026년 6월 1일 오후 12_05_52.png"
  "ChatGPT Image 2026년 6월 1일 오후 12_11_07.png"
  "ChatGPT Image 2026년 6월 1일 오후 12_17_04.png"
  "ChatGPT Image 2026년 6월 1일 오후 01_31_06.png"
)
BG="집중.mp3"
D=0.7   # 크로스페이드 길이(초)
N=6

# 인자: $1 나레이션 파일, $2 출력 파일
make() {
  NARR="$1"; OUT="$2"
  T=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$NARR")
  # L = (T + (N-1)*D) / N
  L=$(awk -v t="$T" -v d="$D" -v n="$N" 'BEGIN{printf "%.4f", (t + (n-1)*d)/n}')
  FADE_ST=$(awk -v t="$T" 'BEGIN{printf "%.4f", t-1.5}')

  echo ">>> $OUT : narration=$T s, clip L=$L s"

  # 입력: 이미지 6장(loop), 나레이션, 배경음악(무한 루프)
  ARGS=()
  for img in "${IMGS[@]}"; do
    ARGS+=(-loop 1 -t "$L" -i "$img")
  done
  ARGS+=(-i "$NARR")
  ARGS+=(-stream_loop -1 -i "$BG")

  # 필터: 각 이미지 720x1280 채움 + 크로스페이드 체인
  FC=""
  for i in $(seq 0 $((N-1))); do
    FC+="[$i:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,setsar=1,fps=30,format=yuv420p[s$i];"
  done
  PREV="s0"
  for k in $(seq 1 $((N-1))); do
    OFF=$(awk -v k="$k" -v l="$L" -v d="$D" 'BEGIN{printf "%.4f", k*(l-d)}')
    if [ "$k" -lt $((N-1)) ]; then OUTLBL="v$k"; else OUTLBL="vid"; fi
    FC+="[$PREV][s$k]xfade=transition=fade:duration=$D:offset=$OFF[$OUTLBL];"
    PREV="$OUTLBL"
  done

  # 오디오: 배경음악 30% + 끝 1.5초 페이드아웃, 나레이션과 믹스(나레이션 풀볼륨)
  AN=$N                      # 나레이션 입력 인덱스
  ABG=$((N+1))               # 배경음악 입력 인덱스
  FC+="[$ABG:a]volume=0.3,atrim=0:$T,afade=t=out:st=$FADE_ST:d=1.5[bg];"
  FC+="[$AN:a][bg]amix=inputs=2:duration=first:normalize=0[aout]"

  ffmpeg -y "${ARGS[@]}" \
    -filter_complex "$FC" \
    -map "[vid]" -map "[aout]" \
    -c:v libx264 -pix_fmt yuv420p -r 30 -profile:v high -crf 20 \
    -c:a aac -b:a 192k -shortest \
    "$OUT"
}

make "Generated Audio June 01, 2026 - 11_00AM.wav" "../video_11_00.mp4"
make "Generated Audio June 01, 2026 - 11_04AM.wav" "../video_11_04.mp4"
echo "ALL DONE"
