The finops_watchdog.py Lambda source and its EventBridge rule belong in
platform/ once populated for real. No other new IaC this phase — Phase
11 is validation and reporting on top of everything built in Phases
00-10, not new infrastructure of its own (finops-scan is application
code, tracked in tools/, not platform/).
