# Shared by disposable UI suites. Build first, verify identities, then install/test.
buko_run_isolated_ui_checks() (
    set -euo pipefail
    # The EXIT trap can run after Bash unwinds function locals on test failure.
    # These variables are already scoped to this disposable subshell.
    harness="$1" app_id="$2" simulator="$3"
    shift 3
    xcodebuild -project "$harness/Buko.xcodeproj" -scheme BukoValidation -configuration Debug \
        -destination "id=$simulator" -derivedDataPath "$harness/DerivedData" \
        CODE_SIGNING_ALLOWED=NO build-for-testing > "$harness/build.log" 2>&1
    run_file="$(python3 Tests/simulator_isolation.py verify "$harness/DerivedData" "$app_id")"
    runner_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$harness/DerivedData/Build/Products/Debug-iphonesimulator/BukoUITests-Runner.app/Info.plist")"
    # These IDs have now been checked against the compiled app and runner.
    cleanup() {
        xcrun simctl uninstall "$simulator" "$app_id" >/dev/null 2>&1 || true
        xcrun simctl uninstall "$simulator" "$runner_id" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT
    cleanup
    xcodebuild -xctestrun "$run_file" -destination "id=$simulator" \
        -parallel-testing-enabled NO -resultBundlePath "$harness/Interactions.xcresult" \
        test-without-building "$@" > "$harness/ui-test.log" 2>&1
)
