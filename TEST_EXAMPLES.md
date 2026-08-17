# Test Output Examples

This document shows actual output from the test-exe binary and dockerify run /opt/steamcmd-bases/bin/test-exe.exe wrapper to help understand the testing system.

## Test Executable Output

### 1. Text Output (Default)

```
╔══════════════════════════════════════════════╗
║     Wine/Proton Compatibility Test Exe       ║
║            Version: 0.1.0                       ║
╚══════════════════════════════════════════════╝

System Information:
  OS: linux
  Architecture: x86_64
  Family: unix

Test Results:
  ✓ PASS - Basic Executable Execution
  ✓ PASS - Environment Variable Access
  ✓ PASS - JSON Serialization
  ✓ PASS - Output Generation
  ✓ PASS - Timing Information

Summary: 5/5 tests passed
```

**Exit Code:** 0 (success)

### 2. Verbose Text Output

```bash
$ ./target/release/test-exe --verbose
```

```
╔══════════════════════════════════════════════╗
║     Wine/Proton Compatibility Test Exe       ║
║            Version: 0.1.0                       ║
╚══════════════════════════════════════════════╝

System Information:
  OS: linux
  Architecture: x86_64
  Family: unix

Test Results:
  ✓ PASS - Basic Executable Execution
      Test that the executable can run and produce output
  ✓ PASS - Environment Variable Access
      Test that the executable can access environment variables
  ✓ PASS - JSON Serialization
      Test that output can be serialized to JSON
  ✓ PASS - Output Generation
      Test that the executable can generate structured output
  ✓ PASS - Timing Information
      Test that current timestamp can be generated

Summary: 5/5 tests passed
```

**Exit Code:** 0 (success)

### 3. JSON Output

```bash
$ ./target/release/test-exe --json
```

```json
{
  "success": true,
  "system": {
    "arch": "x86_64",
    "family": "unix",
    "os": "linux"
  },
  "tests": {
    "all_passed": true,
    "basic_execution": {
      "description": "Test that the executable can run and produce output",
      "name": "Basic Executable Execution",
      "passed": true
    },
    "environment_access": {
      "description": "Test that the executable can access environment variables",
      "name": "Environment Variable Access",
      "passed": true
    },
    "json_serialization": {
      "description": "Test that output can be serialized to JSON",
      "name": "JSON Serialization",
      "passed": true
    },
    "output_generation": {
      "description": "Test that the executable can generate structured output",
      "name": "Output Generation",
      "passed": true
    },
    "tests_passed": 5,
    "timing": {
      "current_time": "2026-01-15T12:34:56.789012Z",
      "description": "Test that current timestamp can be generated",
      "name": "Timing Information",
      "passed": true
    },
    "total_tests": 5
  },
  "timestamp": "2026-01-15T12:34:56.789012Z",
  "version": "0.1.0"
}
```

**Exit Code:** 0 (success)

### 4. JSON Output via jq

```bash
$ ./target/release/test-exe --json | jq '.'
```

Same JSON as above, but formatted by jq.

**Extracting specific fields:**

```bash
$ ./target/release/test-exe --json | jq '.success'
true

$ ./target/release/test-exe --json | jq '.tests | keys'
[
  "all_passed",
  "basic_execution",
  "environment_access",
  "json_serialization",
  "output_generation",
  "tests_passed",
  "timing",
  "total_tests"
]

$ ./target/release/test-exe --json | jq '.tests[] | select(.passed == false)'
(empty - no failed tests)
```

## Test Wrapper Output

### 1. Basic dockerify run /opt/steamcmd-bases/bin/test-exe.exe Execution

```bash
$ docker compose run steamcmd-wine dockerify run /opt/steamcmd-bases/bin/test-exe.exe
```

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Wine/Proton Compatibility Test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Platform: wine
Test executable: /opt/steamcmd-bases/bin/test-exe.exe

→ Running test executable with Wine...

╔══════════════════════════════════════════════╗
║     Wine/Proton Compatibility Test Exe       ║
║            Version: 0.1.0                       ║
╚══════════════════════════════════════════════╝

System Information:
  OS: linux
  Architecture: x86_64
  Family: unix

Test Results:
  ✓ PASS - Basic Executable Execution
  ✓ PASS - Environment Variable Access
  ✓ PASS - JSON Serialization
  ✓ PASS - Output Generation
  ✓ PASS - Timing Information

Summary: 5/5 tests passed

✓ Test output is valid

✓ Tests completed
```

**Exit Code:** 0 (success)

### 2. Proton-Specific Test

```bash
$ docker compose run steamcmd-proton dockerify run --proton /opt/steamcmd-bases/bin/test-exe.exe --json
```

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Wine/Proton Compatibility Test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Platform: proton
Test executable: /opt/steamcmd-bases/bin/test-exe.exe

→ Running test executable with Proton...

{
  "success": true,
  "system": { ... },
  "tests": { ... },
  "timestamp": "2026-01-15T12:34:56.789012Z",
  "version": "0.1.0"
}

✓ Test output is valid JSON

✓ All tests passed
```

**Exit Code:** 0 (success)

### 3. Verbose Mode

```bash
$ docker compose run steamcmd-proton dockerify run --wine /opt/steamcmd-bases/bin/test-exe.exe --verbose
```

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Wine/Proton Compatibility Test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Platform: wine
Test executable: /opt/steamcmd-bases/bin/test-exe.exe

→ Running test executable with Wine...

╔══════════════════════════════════════════════╗
║     Wine/Proton Compatibility Test Exe       ║
║            Version: 0.1.0                       ║
╚══════════════════════════════════════════════╝

System Information:
  OS: linux
  Architecture: x86_64
  Family: unix

Test Results:
  ✓ PASS - Basic Executable Execution
      Test that the executable can run and produce output
  ✓ PASS - Environment Variable Access
      Test that the executable can access environment variables
  ✓ PASS - JSON Serialization
      Test that output can be serialized to JSON
  ✓ PASS - Output Generation
      Test that the executable can generate structured output
  ✓ PASS - Timing Information
      Test that current timestamp can be generated

Summary: 5/5 tests passed

✓ Test output is valid

✓ Tests completed
```

**Exit Code:** 0 (success)

## System Status Output

### Dependency Summary (From deps.sh)

```bash
$ docker compose run steamcmd-proton bash -c 'source /opt/steamcmd-bases/lib/deps.sh && print_deps_summary'
```

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
System Dependencies Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  OS: ubuntu 24.04

  SteamCMD:
    ✓ Installed at /root/.local/share/Steam/steamcmd

  Wine:
    ✓ wine-8.0 (Ubuntu)
    ✓ Prefix: /home/steam/.proton/pfx
    ✓ Prefix initialized

  Proton-GE:
    ✓ 8.26 installed
    ✓ Path: /home/steam/.steam/root/compatibilitytools.d/GE-Proton8.26-1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Error Cases

### 1. Test Executable Not Found

```bash
$ dockerify run /nonexistent/path/test-exe
```

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Wine/Proton Compatibility Test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Platform: proton
Test executable: /nonexistent/path/test-exe

✗ ERROR: Test executable not found at /nonexistent/path/test-exe
```

**Exit Code:** 2

### 2. Wine/Proton Not Available

```bash
# In environment without Wine or Proton installed
$ dockerify run /opt/steamcmd-bases/bin/test-exe.exe
```

```
✗ ERROR: Neither Wine nor Proton detected
```

**Exit Code:** 3

### 3. Invalid Arguments

```bash
$ dockerify run --invalid-flag
```

```
ERROR: Unknown option: --invalid-flag

Wine/Proton Test Runner

Usage: dockerify run /opt/steamcmd-bases/bin/test-exe.exe [OPTIONS]
...
```

**Exit Code:** 4

## GitHub Actions Output

### Workflow Summary

```
Test Compatibility Workflow

✅ build-test-exe: SUCCESS (3 matrix builds)
  ├─ x86_64-unknown-linux-gnu: PASS (3.2s)
  ├─ x86_64-pc-windows-gnu: PASS (5.1s)
  └─ x86_64-apple-darwin: PASS (4.8s)

✅ test-linux: SUCCESS (45s)
  ├─ Run test executable directly: PASS
  ├─ Install Wine: PASS
  └─ Run through Wine: PASS

✅ test-windows: SUCCESS (30s)
  └─ Run test executable (native): PASS

✅ test-macos: SUCCESS (35s)
  ├─ Run test executable directly: PASS
  ├─ Install Homebrew: PASS
  └─ Run through Wine: PASS (optional)

✅ test-docker: SUCCESS (120s)
  ├─ Build base image: PASS
  ├─ Build wine image: PASS
  └─ Build proton image: PASS

✅ compatibility-matrix: SUCCESS

Compatibility Matrix Report:
| Platform | Status | Notes |
|----------|--------|-------|
| Linux (Ubuntu) | ✅ PASS | Direct execution + Wine |
| Windows Server | ✅ PASS | Native execution |
| macOS | ✅ PASS | Direct execution + Wine |
| Docker Images | ✅ PASS | All three targets |
```

## Exit Code Reference

- **0:** All tests passed ✅
- **1:** Some tests failed ❌
- **2:** Test executable not found 📦
- **3:** Wine/Proton not available 🚫
- **4:** Invalid arguments or configuration ⚠️

## Parsing JSON Output

### Extract Success Status

```bash
./target/release/test-exe --json | jq '.success'
# Output: true or false
```

### Count Passed Tests

```bash
./target/release/test-exe --json | jq '.tests.tests_passed'
# Output: 5
```

### Get System Info

```bash
./target/release/test-exe --json | jq '.system'
# Output: {"arch":"x86_64","family":"unix","os":"linux"}
```

### Check Specific Test

```bash
./target/release/test-exe --json | jq '.tests.wine_execution'
# Output: {"description":"...","name":"...","passed":true}
```

### Filter Failed Tests

```bash
./target/release/test-exe --json | jq '.tests[] | select(.passed == false)'
# Output: (empty if all pass, or failed test details)
```

## Integration with CI/CD

### GitHub Actions Validation

```yaml
- name: Run test-exe
  run: |
    OUTPUT=$(./target/release/test-exe --json)
    SUCCESS=$(echo "$OUTPUT" | jq '.success')
    if [ "$SUCCESS" != "true" ]; then
      echo "Test failed!"
      echo "$OUTPUT" | jq .
      exit 1
    fi
```

### Docker Validation

```bash
docker compose run --rm steamcmd-proton bash -c '
  OUTPUT=$(dockerify run /opt/steamcmd-bases/bin/test-exe.exe --json)
  echo "$OUTPUT" | jq .success
'
```

---

These examples demonstrate how the test system works and can be used for validation, debugging, and automation.
