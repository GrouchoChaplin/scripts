#!/usr/bin/env bash
# ------------------------------------------------------------------
# color_test.sh
# Displays all standard ANSI colors (16) and extended 256 colors.
# ------------------------------------------------------------------

echo -e "\n\033[1m== 16 Standard ANSI Colors ==\033[0m"

for attr in 0 1; do  # 0 = normal, 1 = bold/bright
  echo -e "\n\033[1mStyle: ${attr}m\033[0m"
  for color in {30..37}; do
    echo -en "\033[${attr};${color}m ${color}m \033[0m"
  done
  echo
done

echo -e "\n\033[1m== Background Colors ==\033[0m"
for bg in {40..47}; do
  echo -en "\033[${bg}m ${bg}m \033[0m"
done
echo

echo -e "\n\033[1m== Bright Background Colors ==\033[0m"
for bg in {100..107}; do
  echo -en "\033[${bg}m ${bg}m \033[0m"
done
echo

echo -e "\n\033[1m== 256-Color Foreground Table ==\033[0m"

for color in {0..255}; do
  printf "\033[38;5;%sm %3s \033[0m" "$color" "$color"
  if (( (color + 1) % 16 == 0 )); then
    echo
  fi
done

echo -e "\n\033[1m== 256-Color Background Table ==\033[0m"

for color in {0..255}; do
  printf "\033[48;5;%sm %3s \033[0m" "$color" "$color"
  if (( (color + 1) % 16 == 0 )); then
    echo
  fi
done

echo -e "\n\033[1;32m✅ Done!\033[0m\n"
