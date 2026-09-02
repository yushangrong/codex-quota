#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"

fail() {
    print -u2 -- "FAIL: $1"
    exit 1
}

require_file() {
    local file="$1"
    [[ -s "$file" ]] || fail "missing or empty file: ${file#$root/}"
}

require_text() {
    local file="$1"
    local text="$2"
    grep -Fq -- "$text" "$file" || fail "${file#$root/} is missing: $text"
}

require_before() {
    local file="$1"
    local first="$2"
    local second="$3"
    awk -v first="$first" -v second="$second" '
        index($0, first) && !first_line { first_line = NR }
        index($0, second) && !second_line { second_line = NR }
        END { exit !(first_line && second_line && first_line < second_line) }
    ' "$file" || fail "${file#$root/} must place '$first' before '$second'"
}

validate_semantics() {
    local candidate_readme="$1"
    local candidate_ci="$2"
    local candidate_release="$3"

    ruby - "$candidate_readme" "$candidate_ci" "$candidate_release" <<'RUBY'
require "psych"

def policy_assert(condition, message)
  return if condition

  warn "POLICY: #{message}"
  exit 1
end

def load_workflow(file)
  workflow = Psych.safe_load(
    File.read(file),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false,
    filename: file
  )
  policy_assert(workflow.is_a?(Hash), "#{file} must contain a workflow mapping")
  workflow
rescue Psych::SyntaxError => error
  warn "POLICY: invalid workflow YAML in #{file}: #{error.message}"
  exit 1
end

def workflow_triggers(workflow, file)
  triggers = workflow["on"] || workflow[true]
  policy_assert(triggers.is_a?(Hash), "#{file} must define an on trigger mapping")
  triggers
end

def workflow_job(workflow, name, file)
  jobs = workflow["jobs"]
  policy_assert(jobs.is_a?(Hash), "#{file} must define jobs")
  job = jobs[name]
  policy_assert(job.is_a?(Hash), "#{file} must define the #{name} job")
  job
end

def workflow_steps(job, file)
  steps = job["steps"]
  policy_assert(steps.is_a?(Array) && steps.all? { |step| step.is_a?(Hash) }, "#{file} must define valid job steps")
  steps
end

def assert_no_job_runner_context(job, file)
  env = job["env"]
  return unless env.is_a?(Hash)

  unsupported = env.values.grep(String).select { |value| value.include?("${{ runner.") }
  policy_assert(unsupported.empty?, "#{file} job env cannot use the runner context")
end

def assert_no_job_permissions(workflow, file)
  jobs = workflow["jobs"]
  policy_assert(jobs.is_a?(Hash), "#{file} must define jobs")
  jobs.each do |name, job|
    policy_assert(job.is_a?(Hash), "#{file} job #{name} must be a mapping")
    policy_assert(!job.key?("permissions"), "#{file} job #{name} must not override root permissions")
  end
end

def uses_position(steps, action)
  index = steps.index { |step| step["uses"] == action }
  index && [index, 0]
end

def command_position(steps, command)
  steps.each_with_index do |step, step_index|
    run = step["run"]
    next unless run.is_a?(String)

    run.lines.each_with_index do |line, line_index|
      return [step_index, line_index] if line.strip == command
    end
  end
  nil
end

def require_position(steps, kind, value, file)
  position = kind == :uses ? uses_position(steps, value) : command_position(steps, value)
  policy_assert(position, "#{file} is missing semantic #{kind}: #{value}")
  position
end

def assert_order(file, *positions)
  policy_assert(
    positions.each_cons(2).all? { |left, right| (left <=> right) == -1 },
    "#{file} steps are not in the required order"
  )
end

readme_file, ci_file, release_file = ARGV
expected_fields = %w[limit_id used_percent window_minutes resets_at timestamp]
readme_lines = File.readlines(readme_file, encoding: "UTF-8")
privacy_start = readme_lines.index { |line| line.strip == "## 隐私" }
policy_assert(privacy_start, "#{readme_file} is missing the privacy section")
privacy_end = ((privacy_start + 1)...readme_lines.length).find do |index|
  readme_lines[index].start_with?("## ")
end || readme_lines.length
privacy_fields = readme_lines[(privacy_start + 1)...privacy_end].map do |line|
  match = line.match(/^\|\s*`([^`]+)`\s*\|/)
  match && match[1]
end.compact
policy_assert(
  privacy_fields == expected_fields,
  "#{readme_file} privacy fields must be exactly #{expected_fields.join(", ")}; got #{privacy_fields.join(", ")}"
)

ci = load_workflow(ci_file)
ci_triggers = workflow_triggers(ci, ci_file)
policy_assert(ci_triggers.key?("pull_request"), "#{ci_file} must run for pull requests")
ci_push = ci_triggers["push"]
policy_assert(ci_push.is_a?(Hash), "#{ci_file} must define push branches")
policy_assert(ci_push["branches"] == ["main"], "#{ci_file} push must target only main")
policy_assert(ci["permissions"] == { "contents" => "read" }, "#{ci_file} root permissions must be exactly contents: read")
assert_no_job_permissions(ci, ci_file)
ci_job = workflow_job(ci, "test", ci_file)
policy_assert(ci_job["runs-on"] == "macos-15", "#{ci_file} test job must run on macos-15")
assert_no_job_runner_context(ci_job, ci_file)
ci_steps = workflow_steps(ci_job, ci_file)
ci_checkout = require_position(ci_steps, :uses, "actions/checkout@v4", ci_file)
ci_swift = require_position(ci_steps, :run, "swift test", ci_file)
ci_build_policy = require_position(ci_steps, :run, "zsh Tests/Scripts/build-scripts-test.sh", ci_file)
ci_repo_policy = require_position(ci_steps, :run, "zsh Tests/Scripts/repository-policy-test.sh", ci_file)
assert_order(ci_file, ci_checkout, ci_swift, ci_build_policy, ci_repo_policy)

ci_windows_job = workflow_job(ci, "windows", ci_file)
policy_assert(ci_windows_job["runs-on"] == "windows-latest", "#{ci_file} windows job must run on windows-latest")
assert_no_job_runner_context(ci_windows_job, ci_file)
ci_windows_steps = workflow_steps(ci_windows_job, ci_file)
ci_windows_checkout = require_position(ci_windows_steps, :uses, "actions/checkout@v4", ci_file)
ci_windows_dotnet = require_position(ci_windows_steps, :uses, "actions/setup-dotnet@v4", ci_file)
ci_windows_build = require_position(ci_windows_steps, :run, "dotnet build windows/CodexQuota.Windows/CodexQuota.Windows.csproj --configuration Release", ci_file)
ci_windows_test = require_position(ci_windows_steps, :run, "dotnet run --project windows/CodexQuota.Windows.Tests/CodexQuota.Windows.Tests.csproj --configuration Release -- Tests/Fixtures", ci_file)
assert_order(ci_file, ci_windows_checkout, ci_windows_dotnet, ci_windows_build, ci_windows_test)

release = load_workflow(release_file)
release_triggers = workflow_triggers(release, release_file)
policy_assert(release_triggers.keys == ["push"], "#{release_file} must trigger only on push")
release_push = release_triggers["push"]
policy_assert(release_push.is_a?(Hash) && release_push["tags"] == ["v*"], "#{release_file} must trigger only on v* tags")
policy_assert(release["permissions"] == { "contents" => "write" }, "#{release_file} root permissions must be exactly contents: write")
assert_no_job_permissions(release, release_file)
release_job = workflow_job(release, "release", release_file)
policy_assert(release_job["runs-on"] == "macos-15", "#{release_file} release job must run on macos-15")
assert_no_job_runner_context(release_job, release_file)
release_steps = workflow_steps(release_job, release_file)
release_checkout = require_position(release_steps, :uses, "actions/checkout@v4", release_file)
release_swift = require_position(release_steps, :run, "swift test", release_file)
release_build_policy = require_position(release_steps, :run, "zsh Tests/Scripts/build-scripts-test.sh", release_file)
release_repo_policy = require_position(release_steps, :run, "zsh Tests/Scripts/repository-policy-test.sh", release_file)
release_build = require_position(release_steps, :run, 'zsh scripts/build-dmg.sh "$version"', release_file)
release_verify = require_position(release_steps, :run, 'zsh scripts/verify-release.sh "dist/Codex Quota.app"', release_file)
release_publish = require_position(release_steps, :uses, "softprops/action-gh-release@v2", release_file)
assert_order(
  release_file,
  release_checkout,
  release_swift,
  release_build_policy,
  release_repo_policy,
  release_build,
  release_verify,
  release_publish
)

build_step_index = release_steps.index { |step| step["name"] == "Build and verify tagged release" }
policy_assert(build_step_index, "#{release_file} is missing the named build and verify step")
policy_assert(
  release_build.first == build_step_index && release_verify.first == build_step_index,
  "#{release_file} build and verify commands must belong to the named release step"
)
build_step = release_steps[build_step_index]
policy_assert(build_step["shell"] == "zsh {0}", "#{release_file} build and verify step must use shell: zsh {0}")
build_run = build_step["run"]
[
  "set -euo pipefail",
  'tag="$GITHUB_REF_NAME"',
  'version="${GITHUB_REF_NAME#v}"',
  '[[ "$version" =~ \'^[0-9]+(\\.[0-9]+){0,2}$\' ]] || { print -u2 -- "invalid release version: $version"; exit 1; }',
  '[[ "$tag" == "v$version" ]] || { print -u2 -- "release tag was not normalized: $tag"; exit 1; }'
].each do |command|
  policy_assert(build_run.lines.any? { |line| line.strip == command }, "#{release_file} build step is missing: #{command}")
end

publish_step = release_steps[release_publish.first]
publish_with = publish_step["with"]
policy_assert(publish_with.is_a?(Hash), "#{release_file} publish step must define with")
policy_assert(publish_with["fail_on_unmatched_files"] == true, "#{release_file} must fail on unmatched release assets")
assets = publish_with["files"].to_s.lines.map(&:strip).reject(&:empty?)
policy_assert(assets == ["dist/*.dmg", "dist/*.sha256"], "#{release_file} must upload only DMG and SHA-256 assets")

windows_release_job = workflow_job(release, "windows-release", release_file)
policy_assert(windows_release_job["needs"] == "release", "#{release_file} windows-release must wait for the macOS release")
policy_assert(windows_release_job["runs-on"] == "windows-latest", "#{release_file} windows-release job must run on windows-latest")
assert_no_job_runner_context(windows_release_job, release_file)
windows_release_steps = workflow_steps(windows_release_job, release_file)
windows_release_checkout = require_position(windows_release_steps, :uses, "actions/checkout@v4", release_file)
windows_release_dotnet = require_position(windows_release_steps, :uses, "actions/setup-dotnet@v4", release_file)
windows_release_test = require_position(windows_release_steps, :run, "dotnet run --project windows/CodexQuota.Windows.Tests/CodexQuota.Windows.Tests.csproj --configuration Release -- Tests/Fixtures", release_file)
windows_release_build = require_position(windows_release_steps, :run, "pwsh -File scripts/build-windows.ps1 -Version $version", release_file)
windows_release_publish = require_position(windows_release_steps, :uses, "softprops/action-gh-release@v2", release_file)
assert_order(
  release_file,
  windows_release_checkout,
  windows_release_dotnet,
  windows_release_test,
  windows_release_build,
  windows_release_publish
)
windows_publish_step = windows_release_steps[windows_release_publish.first]
windows_publish_with = windows_publish_step["with"]
policy_assert(windows_publish_with.is_a?(Hash), "#{release_file} Windows publish step must define with")
policy_assert(windows_publish_with["fail_on_unmatched_files"] == true, "#{release_file} Windows publish must fail on unmatched assets")
windows_assets = windows_publish_with["files"].to_s.lines.map(&:strip).reject(&:empty?)
policy_assert(windows_assets == ["dist/*.zip", "dist/*.sha256"], "#{release_file} must upload only Windows ZIP and SHA-256 assets from windows-release")
RUBY
}

run_policy_self_tests() (
    set -euo pipefail

    local self_test_root
    self_test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-policy.XXXXXX")"
    trap 'rm -rf -- "$self_test_root"' EXIT

    cp "$ci" "$self_test_root/ci-invalid.yml"
    print -r -- 'invalid: [' >> "$self_test_root/ci-invalid.yml"
    if validate_semantics "$readme" "$self_test_root/ci-invalid.yml" "$release" >/dev/null 2>&1; then
        fail "policy self-test accepted invalid workflow YAML"
    fi

    cp "$ci" "$self_test_root/ci-commented.yml"
    ruby -e '
        file = ARGV.fetch(0)
        text = File.read(file)
        File.write(file, text.sub("run: swift test", "# run: swift test"))
    ' "$self_test_root/ci-commented.yml"
    if validate_semantics "$readme" "$self_test_root/ci-commented.yml" "$release" >/dev/null 2>&1; then
        fail "policy self-test accepted swift test only as a comment"
    fi

    cp "$readme" "$self_test_root/README-extra-field.md"
    ruby -e '
        file = ARGV.fetch(0)
        text = File.read(file)
        row = "| `timestamp` | 在多个事件中选择最新有效值 |"
        File.write(file, text.sub(row, row + "\n| `account_id` | forbidden sixth field |"))
    ' "$self_test_root/README-extra-field.md"
    if validate_semantics "$self_test_root/README-extra-field.md" "$ci" "$release" >/dev/null 2>&1; then
        fail "policy self-test accepted a sixth privacy field"
    fi

    cp "$ci" "$self_test_root/ci-extra-root-permission.yml"
    ruby -e '
        file = ARGV.fetch(0)
        text = File.read(file)
        File.write(file, text.sub("  contents: read", "  contents: read\n  id-token: write"))
    ' "$self_test_root/ci-extra-root-permission.yml"
    if validate_semantics "$readme" "$self_test_root/ci-extra-root-permission.yml" "$release" >/dev/null 2>&1; then
        fail "policy self-test accepted an extra root permission"
    fi

    cp "$release" "$self_test_root/release-job-permission.yml"
    ruby -e '
        file = ARGV.fetch(0)
        text = File.read(file)
        File.write(file, text.sub(
            "  release:\n    runs-on:",
            "  release:\n    permissions:\n      contents: write\n    runs-on:"
        ))
    ' "$self_test_root/release-job-permission.yml"
    if validate_semantics "$readme" "$ci" "$self_test_root/release-job-permission.yml" >/dev/null 2>&1; then
        fail "policy self-test accepted job-level permissions"
    fi

    cp "$release" "$self_test_root/release-shell-missing.yml"
    ruby -e '
        file = ARGV.fetch(0)
        text = File.read(file)
        File.write(file, text.sub("        shell: zsh {0}\n", ""))
    ' "$self_test_root/release-shell-missing.yml"
    if validate_semantics "$readme" "$ci" "$self_test_root/release-shell-missing.yml" >/dev/null 2>&1; then
        fail "policy self-test accepted a missing build shell"
    fi

    cp "$release" "$self_test_root/release-shell-changed.yml"
    ruby -e '
        file = ARGV.fetch(0)
        text = File.read(file)
        File.write(file, text.sub("shell: zsh {0}", "shell: bash"))
    ' "$self_test_root/release-shell-changed.yml"
    if validate_semantics "$readme" "$ci" "$self_test_root/release-shell-changed.yml" >/dev/null 2>&1; then
        fail "policy self-test accepted a changed build shell"
    fi

    print -- "PASS: policy mutation self-tests"
)

readme="$root/README.md"
license="$root/LICENSE"
security="$root/SECURITY.md"
preview="$root/docs/images/preview.svg"
ci="$root/.github/workflows/ci.yml"
release="$root/.github/workflows/release.yml"
gitignore="$root/.gitignore"

for required_file in "$readme" "$license" "$security" "$preview" "$ci" "$release" "$gitignore"; do
    require_file "$required_file"
done

readme_sections=(
    "## 界面预览"
    "## 非 OpenAI 官方项目"
    "## 系统要求"
    "## 下载"
    "## 首次打开"
    "## 辅助功能权限"
    "## 使用方法"
    "## 颜色说明"
    "## 等待与过期状态"
    "## 设置"
    "## 隐私"
    "## 卸载"
    "## 故障排查"
    "## 开发"
    "## 发布"
    "## 许可证"
)
for (( index = 1; index < ${#readme_sections}; index++ )); do
    require_before "$readme" "${readme_sections[index]}" "${readme_sections[index + 1]}"
done

require_text "$readme" "![界面预览](docs/images/preview.svg)"
require_text "$readme" "不是运行截图"
require_text "$readme" "未经过 Apple 公证"
require_text "$readme" "右键"
require_text "$readme" "打开"
require_text "$readme" "macOS 13"
require_text "$readme" "Windows 10 2004"
require_text "$readme" "Codex-Quota-vX.Y.Z-Windows-x64.zip"
require_text "$readme" '%LOCALAPPDATA%\CodexQuota\snapshot.json'
require_text "$readme" "dotnet build windows/CodexQuota.Windows/CodexQuota.Windows.csproj"
require_text "$readme" "辅助功能权限仅用于读取 Codex 窗口位置"
require_text "$readme" '~/.codex/sessions'
require_text "$readme" '~/.codex/archived_sessions'
require_text "$readme" "limit_id"
require_text "$readme" "used_percent"
require_text "$readme" "window_minutes"
require_text "$readme" "resets_at"
require_text "$readme" "timestamp"
require_text "$readme" "不发起网络请求"
require_text "$readme" "登录项"
require_text "$readme" "Application Support"
require_text "$readme" "Logs"
require_text "$readme" "shasum -a 256 -c Codex-Quota-v0.2.0-macOS-universal.dmg.sha256"

require_text "$license" "MIT License"
require_text "$license" "Permission is hereby granted, free of charge"
require_text "$security" "安全漏洞"
require_text "$security" "私下报告"
require_text "$preview" "界面预览"
require_text "$preview" "Codex 63% · 3天"

for ignored in ".worktrees/" ".superpowers/" ".build/" "dist/" ".DS_Store" "*.p12" "*.mobileprovision" "bin/" "obj/"; do
    require_text "$gitignore" "$ignored"
done

validate_semantics "$readme" "$ci" "$release"
run_policy_self_tests

print -- "PASS: public repository policy"
