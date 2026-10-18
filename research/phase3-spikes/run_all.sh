#!/bin/zsh
B=dd/Build/Products/Release/mlxspike
F=Spike/.build/release/fmspike
for pair in "Qwen3-4B-Instruct-2507-4bit qwen3-4b-2507" "Qwen3.5-2B-MLX-4bit qwen3.5-2b" "gemma-4-e2b-it-4bit gemma4-e2b" "Phi-4-mini-instruct-4bit phi4-mini"; do
  set -- ${=pair}
  echo "### $2 paste"; $B models/$1 $2 paste fixtures results/mlx2-$2-paste.jsonl split exact cachelimit=512 2>&1 | grep -E "^loaded|footprint|Error"
  echo "### $2 setreq"; $B models/$1 $2 setreq - results/mlx2-$2-setreq.jsonl cachelimit=512 2>&1 | grep -E "^loaded|footprint|Error"
done
echo "### fm"
$F paste fixtures results/fm2-split-hints-exact.jsonl mode=hints split exact repeat=3 > /dev/null 2>&1
$F setreq results/fm2-setreq-cold.jsonl repeat=2 > /dev/null 2>&1
$F setreq results/fm2-setreq-prewarm.jsonl prewarm > /dev/null 2>&1
$F paste fixtures results/fm2-chunk-budget250.jsonl mode=hints split exact budget=250 > /dev/null 2>&1
echo ALLDONE
