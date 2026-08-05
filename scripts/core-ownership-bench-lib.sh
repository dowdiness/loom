#!/usr/bin/env bash

# Deterministic validation and comparison core for the core-ownership profile.
# Callers own filesystem, Git, Moon, and artifact I/O.

core_ownership_schedule() {
  local runs="$1"
  local run
  for ((run = 1; run <= runs; run++)); do
    if ((run % 2 == 1)); then
      printf 'baseline\t%d\n' "$run"
      printf 'candidate\t%d\n' "$run"
    else
      printf 'candidate\t%d\n' "$run"
      printf 'baseline\t%d\n' "$run"
    fi
  done
}

core_ownership_validate_release_runs() {
  local runs="$1"
  if [[ "$runs" != "5" ]]; then
    printf 'core-ownership release profile requires exactly 5 samples per revision; received %s\n' \
      "$runs" >&2
    return 1
  fi
}

core_ownership_validate_runner_provenance() {
  local repo_root="$1" candidate_sha="$2"
  local runner_sha status
  runner_sha=$(git -C "$repo_root" rev-parse HEAD)
  if [[ "$runner_sha" != "$candidate_sha" ]]; then
    printf 'core-ownership runner HEAD %s does not match candidate %s\n' \
      "$runner_sha" "$candidate_sha" >&2
    return 1
  fi
  status=$(git -C "$repo_root" status --porcelain \
    --untracked-files=all --ignore-submodules=none)
  if [[ -n "$status" ]]; then
    printf 'core-ownership runner checkout must be clean; found:\n%s\n' \
      "$status" >&2
    return 1
  fi
}

core_ownership_snapshot_file() {
  local repo_root="$1" commit="$2" path="$3" output="$4"
  local expected_blob actual_blob
  expected_blob=$(git -C "$repo_root" rev-parse "${commit}:${path}")
  git -C "$repo_root" show "${commit}:${path}" > "$output"
  actual_blob=$(git hash-object "$output")
  if [[ "$actual_blob" != "$expected_blob" ]]; then
    printf 'core-ownership snapshot mismatch for %s: expected %s, got %s\n' \
      "$path" "$expected_blob" "$actual_blob" >&2
    return 1
  fi
  printf '%s\n' "$expected_blob"
}

core_ownership_validate_policy() {
  local policy_file="$1"
  awk -F '\t' '
    /^[[:space:]]*#/ {
      if ($0 == "# policy_version=1") {
        version_count++
      } else if ($0 ~ /^# max_relative_mad_percent=/) {
        split($0, setting, "=")
        if (setting[2] !~ /^[0-9]+([.][0-9]+)?$/ || setting[2] + 0 <= 0) {
          print "policy: invalid max_relative_mad_percent: " $0 > "/dev/stderr"
          bad = 1
        } else {
          stability_count++
        }
      } else if ($0 ~ /^[[:space:]]*# policy_version=/) {
        print "policy: unsupported version: " $0 > "/dev/stderr"
        bad = 1
      }
      next
    }
    NF == 0 { next }
    NF != 6 || $1 == "" ||
      $2 !~ /^[0-9]+([.][0-9]+)?$/ ||
      $3 !~ /^[0-9]+([.][0-9]+)?$/ ||
      ($4 != "required" && $4 != "optional") ||
      ($5 != "gated" && $5 != "informational") ||
      $6 !~ /[^[:space:]]/ {
      print "policy: malformed row: " $0 > "/dev/stderr"
      bad = 1
      next
    }
    {
      if ($1 in seen) {
        print "policy: duplicate benchmark: " $1 > "/dev/stderr"
        bad = 1
      }
      seen[$1] = 1
    }
    END {
      if (version_count != 1) {
        print "policy: exactly one # policy_version=1 declaration required" > "/dev/stderr"
        bad = 1
      }
      if (stability_count != 1) {
        print "policy: exactly one # max_relative_mad_percent=<positive number> declaration required" > "/dev/stderr"
        bad = 1
      }
      exit bad
    }
  ' "$policy_file"
}

core_ownership_validate_required_rows() {
  local policy_file="$1" sample_file="$2" label="$3"
  awk -F '\t' -v label="$label" '
    NR == FNR {
      if ($0 !~ /^[[:space:]]*#/ && NF > 0 && $4 == "required") {
        required[$1] = 1
      }
      next
    }
    { present[$1] = 1 }
    END {
      for (name in required) {
        if (!(name in present)) {
          printf "%s: missing required benchmark: %s\n", label, name > "/dev/stderr"
          bad = 1
        }
      }
      exit bad
    }
  ' "$policy_file" "$sample_file"
}

core_ownership_stability_report() {
  local policy_file="$1"
  shift
  awk -F '\t' -v policy_file="$policy_file" '
    BEGIN {
      while ((getline line < policy_file) > 0) {
        if (line ~ /^# max_relative_mad_percent=/) {
          split(line, setting, "=")
          threshold = setting[2] + 0
          continue
        }
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
        split(line, field, "\t")
        if (field[4] == "required") required[field[1]] = 1
      }
      close(policy_file)
      expected = ARGC - 1
    }
    $1 in required {
      count[$1]++
      value[$1, count[$1]] = $2 + 0
    }
    END {
      for (name in required) {
        if (count[name] != expected) {
          printf "stability: %s has %d samples, expected %d\n", name, count[name], expected > "/dev/stderr"
          bad = 1
          continue
        }
        for (i = 1; i <= count[name]; i++) sorted[i] = value[name, i]
        for (i = 2; i <= count[name]; i++) {
          current = sorted[i]
          j = i - 1
          while (j >= 1 && sorted[j] > current) {
            sorted[j + 1] = sorted[j]
            j--
          }
          sorted[j + 1] = current
        }
        median = sorted[(count[name] + 1) / 2]
        for (i = 1; i <= count[name]; i++) {
          delta = sorted[i] - median
          deviation[i] = delta < 0 ? -delta : delta
        }
        for (i = 2; i <= count[name]; i++) {
          current = deviation[i]
          j = i - 1
          while (j >= 1 && deviation[j] > current) {
            deviation[j + 1] = deviation[j]
            j--
          }
          deviation[j + 1] = current
        }
        mad = deviation[(count[name] + 1) / 2]
        relative_mad = median > 0 ? mad / median * 100 : (mad > 0 ? 1e99 : 0)
        status = "OK"
        if (relative_mad > threshold) {
          status = "UNSTABLE"
          bad = 1
        }
        printf "%s\t%s\t%.2f\t%.2f\t%.2f%%\t%.2f%%\n",
          status, name, median, mad, relative_mad, threshold
        for (i = 1; i <= count[name]; i++) {
          delete sorted[i]
          delete deviation[i]
        }
      }
      exit bad
    }
  ' "$@" | sort -t $'\t' -k2,2
}

core_ownership_medians() {
  local expected_runs="$1"
  shift
  awk -F '\t' -v expected="$expected_runs" '
    NF != 2 || $1 == "" || $2 !~ /^[0-9]+([.][0-9]+)?$/ {
      print "median: malformed sample row: " $0 > "/dev/stderr"
      bad = 1
      next
    }
    {
      count[$1]++
      value[$1, count[$1]] = $2 + 0
    }
    END {
      for (name in count) {
        if (count[name] != expected) {
          printf "median: %s has %d samples, expected %d\n", name, count[name], expected > "/dev/stderr"
          bad = 1
          continue
        }
        for (i = 1; i <= count[name]; i++) sorted[i] = value[name, i]
        for (i = 2; i <= count[name]; i++) {
          current = sorted[i]
          j = i - 1
          while (j >= 1 && sorted[j] > current) {
            sorted[j + 1] = sorted[j]
            j--
          }
          sorted[j + 1] = current
        }
        if (expected % 2 == 1) {
          median = sorted[(expected + 1) / 2]
        } else {
          median = (sorted[expected / 2] + sorted[expected / 2 + 1]) / 2
        }
        printf "%s\t%.2f\n", name, median
        for (i = 1; i <= count[name]; i++) delete sorted[i]
      }
      exit bad
    }
  ' "$@" | sort
}

core_ownership_compare_medians() {
  local policy_file="$1" baseline_file="$2" candidate_file="$3"
  awk -F '\t' -v policy_file="$policy_file" '
    BEGIN {
      while ((getline line < policy_file) > 0) {
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
        split(line, field, "\t")
        relative[field[1]] = field[2] + 0
        absolute[field[1]] = field[3] + 0
        required[field[1]] = field[4]
        mode[field[1]] = field[5]
        reason[field[1]] = field[6]
      }
      close(policy_file)
    }
    NR == FNR {
      baseline[$1] = $2 + 0
      next
    }
    {
      candidate[$1] = $2 + 0
      name = $1
      if (!(name in relative)) next
      seen[name] = 1
      if (!(name in baseline)) {
        printf "MISSING_BASELINE\t%s\n", name
        bad = 1
        next
      }
      base = baseline[name]
      current = candidate[name]
      delta = current - base
      percent = base > 0 ? delta / base * 100 : 0
      status = "OK"
      if (mode[name] == "informational") {
        status = "INFO"
      } else if (percent > relative[name] && delta > absolute[name]) {
        status = "REGRESSION"
        bad = 1
      }
      printf "%s\t%s\t%.2f\t%.2f\t%+.2f\t%+.2f%%\t%.2f%%\t%.2f\t%s\t%s\n",
        status, name, base, current, delta, percent, relative[name], absolute[name], mode[name], reason[name]
    }
    END {
      for (name in required) {
        if (required[name] == "required" && !(name in seen)) {
          printf "MISSING_CANDIDATE\t%s\n", name
          bad = 1
        }
      }
      exit bad
    }
  ' "$baseline_file" "$candidate_file"
}

core_ownership_environment_matches() {
  cmp -s "$1" "$2"
}
