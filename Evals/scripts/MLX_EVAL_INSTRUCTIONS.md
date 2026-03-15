#!/usr/bin/env python3
"""
Build instructions for MLX baseline evaluation.

The eval_formatter.swift tool needs to be compiled within the Zphyr project.
"""

print("""
=== MLX BASELINE EVALUATION — BUILD & RUN INSTRUCTIONS ===

The Swift tool must be compiled within the Zphyr Xcode project.

STEP 1: Add eval_formatter.swift to Zphyr target
----------------------------------------------------
1. Open Zphyr.xcodeproj in Xcode
2. Drag eval_formatter.swift into the Zphyr target
3. Build → Build (⌘+B)

STEP 2: Build the evaluator
----------------------------------------------------
cd Zphyr
swiftc eval_formatter.swift -o eval_formatter \\
  -I . -I ../Evals \\
  $(swift package deps | grep mlx | sed 's/^/-L /') \\
  -lmlx -lmlxswift -lmlxlm -lmlxlmcommon

STEP 3: Run evaluation
----------------------------------------------------
./eval_formatter ../Evals/datasets/splits/test.jsonl \\
  > ../Evals/baselines/mlx_baseline_outputs.jsonl

STEP 4: Score outputs
----------------------------------------------------
cd ../Evals
python scripts/score_mlx_baseline.py \\
  --input baselines/mlx_baseline_outputs.jsonl \\
  --output baselines/mlx_baseline_metrics.json

ALTERNATIVE: Use existing test infrastructure
----------------------------------------------------
If you prefer not to build a separate tool, you can add
a test method to ZphyrTests/EvalHarnessRunner.swift:

```swift
func testL2_NewSeedSplit() async throws {
    // Load and evaluate Evals/datasets/splits/test.jsonl
    let testPath = "../Evals/datasets/splits/test.jsonl"
    // ... evaluation code ...
}
```

Then run:
```bash
xcodebuild test -scheme Zphyr \\
  -only-testing:ZphyrTests/EvalHarnessRunner/testL2_NewSeedSplit
```

""")
