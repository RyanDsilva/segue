#!/bin/zsh
B=dd/Build/Products/Release/mlxspike
F=Spike/.build/release/fmspike
for pair in "Qwen3-4B-Instruct-2507-4bit qwen3-4b-2507" "Qwen3.5-2B-MLX-4bit qwen3.5-2b" "gemma-4-e2b-it-4bit gemma4-e2b" "Phi-4-mini-instruct-4bit phi4-mini"; do
  set -- ${=pair}
  echo "### $2 setreq v3"; $B models/$1 $2 setreq - results/mlx4-$2-setreq-v3.jsonl v3 cachelimit=512 2>&1 | grep -E "^loaded|footprint|Error"
done
echo "### fm"
$F setreq results/fm4-setreq-v3.jsonl v3 repeat=2 > /dev/null 2>&1
echo ALLDONE
