#!/bin/zsh
B=dd/Build/Products/Release/mlxspike
for pair in "Qwen3-4B-Instruct-2507-4bit qwen3-4b-2507" "Qwen3.5-2B-MLX-4bit qwen3.5-2b" "gemma-4-e2b-it-4bit gemma4-e2b" "Phi-4-mini-instruct-4bit phi4-mini"; do
  set -- ${=pair}
  echo "### $2 paste"; $B models/$1 $2 paste fixtures results/mlx-$2-paste.jsonl split 2>&1 | grep -E "^loaded|final|Error|error" 
  echo "### $2 setreq"; $B models/$1 $2 setreq - results/mlx-$2-setreq.jsonl 2>&1 | grep -E "^loaded|final|Error|error"
done
echo ALLDONE
