use serde_json::{json, Value};
use std::env;

mod vulkan;

fn main() {
    let args: Vec<String> = env::args().collect();

    // Parse command-line arguments
    let verbose = args.contains(&"--verbose".to_string());
    let check_vulkan = args.contains(&"--check-vulkan".to_string());
    let format = if args.contains(&"--json".to_string()) {
        "json"
    } else {
        "text"
    };

    // Gather system information
    let system_info = gather_system_info();
    let tests = run_tests(check_vulkan);

    // Build output
    let output = match format {
        "json" => {
            let json_output = json!({
                "timestamp": chrono::Utc::now().to_rfc3339(),
                "version": env!("CARGO_PKG_VERSION"),
                "system": system_info,
                "tests": tests,
                "success": tests.get("all_passed").and_then(|v| v.as_bool()).unwrap_or(false),
            });
            serde_json::to_string_pretty(&json_output).unwrap()
        }
        _ => format_text_output(&system_info, &tests, verbose),
    };

    println!("{}", output);

    // Exit with appropriate code
    let all_passed = tests
        .get("all_passed")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    std::process::exit(if all_passed { 0 } else { 1 });
}

fn gather_system_info() -> Value {
    json!({
        "os": std::env::consts::OS,
        "arch": std::env::consts::ARCH,
        "family": std::env::consts::FAMILY,
    })
}

fn run_tests(check_vulkan: bool) -> Value {
    let mut results = json!({});

    // Test 1: Basic execution
    let basic_exec = true;
    results["basic_execution"] = json!({
        "name": "Basic Executable Execution",
        "passed": basic_exec,
        "description": "Test that the executable can run and produce output"
    });

    // Test 2: Environment access
    let has_env = env::var("PATH").is_ok();
    results["environment_access"] = json!({
        "name": "Environment Variable Access",
        "passed": has_env,
        "description": "Test that the executable can access environment variables"
    });

    // Test 3: Output generation
    let output_works = true;
    results["output_generation"] = json!({
        "name": "Output Generation",
        "passed": output_works,
        "description": "Test that the executable can generate structured output"
    });

    // Test 4: JSON serialization
    let json_works = serde_json::to_string(&results).is_ok();
    results["json_serialization"] = json!({
        "name": "JSON Serialization",
        "passed": json_works,
        "description": "Test that output can be serialized to JSON"
    });

    // Test 5: Timing
    let timing_works = true;
    results["timing"] = json!({
        "name": "Timing Information",
        "passed": timing_works,
        "description": "Test that current timestamp can be generated",
        "current_time": chrono::Utc::now().to_rfc3339()
    });

    // Test 6 (opt-in): Vulkan availability. Off by default so platforms
    // without a Vulkan loader (e.g. bare CI runners) don't fail the whole
    // suite - pass --check-vulkan to require it, e.g. as a container build
    // smoke test that a software Vulkan device (lavapipe) is wired up.
    if check_vulkan {
        let (passed, detail) = vulkan::check();
        results["vulkan_available"] = json!({
            "name": "Vulkan Availability",
            "passed": passed,
            "description": "Test that a Vulkan instance can be created and a physical device found (required by DXVK/Proton)",
            "detail": detail
        });
    }

    // Calculate overall status
    let passed_flags: Vec<bool> = results
        .as_object()
        .map(|obj| {
            obj.values()
                .filter_map(|v| v.get("passed").and_then(|p| p.as_bool()))
                .collect()
        })
        .unwrap_or_default();
    let all_passed = passed_flags.iter().all(|p| *p);

    results["all_passed"] = json!(all_passed);
    results["total_tests"] = json!(passed_flags.len());
    results["tests_passed"] = json!(passed_flags.iter().filter(|p| **p).count());

    results
}

fn format_text_output(system_info: &Value, tests: &Value, verbose: bool) -> String {
    let mut output = String::new();

    output.push_str("╔══════════════════════════════════════════════╗\n");
    output.push_str("║     Wine/Proton Compatibility Test Exe       ║\n");
    output.push_str("║            Version: ");
    output.push_str(env!("CARGO_PKG_VERSION"));
    output.push_str("                       ║\n");
    output.push_str("╚══════════════════════════════════════════════╝\n\n");

    output.push_str("System Information:\n");
    output.push_str(&format!(
        "  OS: {}\n",
        system_info
            .get("os")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
    ));
    output.push_str(&format!(
        "  Architecture: {}\n",
        system_info
            .get("arch")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
    ));
    output.push_str(&format!(
        "  Family: {}\n\n",
        system_info
            .get("family")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
    ));

    output.push_str("Test Results:\n");
    if let Some(obj) = tests.as_object() {
        for (key, value) in obj {
            if key == "all_passed" || key == "total_tests" || key == "tests_passed" {
                continue;
            }

            if let Some(test_obj) = value.as_object() {
                let name = test_obj.get("name").and_then(|v| v.as_str()).unwrap_or(key);
                let passed = test_obj
                    .get("passed")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                let status = if passed { "✓ PASS" } else { "✗ FAIL" };
                output.push_str(&format!("  {} - {}\n", status, name));

                if verbose {
                    if let Some(desc) = test_obj.get("description").and_then(|v| v.as_str()) {
                        output.push_str(&format!("      {}\n", desc));
                    }
                    if let Some(detail) = test_obj.get("detail").and_then(|v| v.as_str()) {
                        output.push_str(&format!("      {}\n", detail));
                    }
                }
            }
        }
    }

    output.push_str("\n");
    if let (Some(passed), Some(total)) = (
        tests.get("tests_passed").and_then(|v| v.as_u64()),
        tests.get("total_tests").and_then(|v| v.as_u64()),
    ) {
        output.push_str(&format!("Summary: {}/{} tests passed\n", passed, total));
    }

    output
}
