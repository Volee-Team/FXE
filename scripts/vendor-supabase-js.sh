#!/usr/bin/env bash
# vendor-supabase-js.sh: write web/vendor/ from the supabase-js version pinned
# in web/package.json, or (--check) prove the committed copy still matches it.
#
#   (cd web && npm ci) && bash scripts/vendor-supabase-js.sh     # write
#   bash scripts/vendor-supabase-js.sh --check                    # CI, web job
#
# WHY (MVP audit 2026-09-27, item 17). index.html and reset.html imported
# https://esm.sh/@supabase/supabase-js@2: a floating major, resolved again on
# every page load, running with Tara's admin session. An esm.sh outage, or a
# 2.x release that changed something the pages rely on, would take down the
# admin site and every password reset on a day nobody deployed anything, and
# deploy-web.sh's byte-for-byte check could not see it. That day, esm.sh was
# already serving 2.117.2, a version nobody here had chosen or tested.
#
# WHAT. The package's own browser bundle, dist/umd/supabase.js: one script,
# every dependency inlined, no import of anything. As published it only sets
# a global, so two export lines go after it and the pages import it as a
# module by relative path. Nothing in the bundle is edited; the header records
# the sha256 of the published file so anyone can check that.
#
# PROVENANCE. npm ci refuses a tarball whose sha512 differs from
# web/package-lock.json, and --check compares the committed file with one
# rebuilt from that tarball, byte for byte. So the served bytes are tied to
# the lockfile, not to whatever a CDN answered.
#
# UPGRADES. Dependabot's npm entry for /web proposes the new pin. The web job
# then fails at --check until someone runs this script and commits
# web/vendor/, which is also when the browser suite first runs against the
# new version. That is the point: a new supabase-js reaches Tara only after
# the suite has passed with it.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=${SUPABASE_JS_DIR:-web/node_modules/@supabase/supabase-js}
OUT=web/vendor
MODE=${1:-write}

want=$(node -p 'require("./web/package.json").devDependencies["@supabase/supabase-js"] || ""')
if ! [[ "$want" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "web/package.json must pin @supabase/supabase-js to one exact version (found '$want')." >&2
  exit 1
fi
if [ ! -f "$PKG/package.json" ]; then
  echo "No $PKG. Run: (cd web && npm ci)" >&2
  exit 1
fi
have=$(node -p "require('./$PKG/package.json').version")
if [ "$have" != "$want" ]; then
  echo "Installed supabase-js is $have, the pin is $want. Run: (cd web && npm ci)" >&2
  exit 1
fi

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
UMD="$PKG/dist/umd/supabase.js"
sum=$(sha256 "$UMD")

build() { # $1: directory to write into
  {
    printf '%s\n' \
      "// @supabase/supabase-js $want, the npm package's dist/umd/supabase.js" \
      "// (sha256 $sum) unchanged, then two export lines so a page can import it." \
      "// Written by scripts/vendor-supabase-js.sh from the pin in web/package.json." \
      "// Do not edit by hand. Licences: LICENSES.txt beside this file."
    cat "$UMD"
    printf '\n;\nexport const createClient = supabase.createClient;\nexport default supabase;\n'
  } > "$1/supabase-js.js"

  # MIT asks that the notice travel with the code. The bundle inlines
  # supabase-js's own dependencies, so every package under it is listed.
  node -e '
    const fs = require("fs"), path = require("path");
    const root = path.resolve(process.argv[1], "..", "..");   // .../node_modules
    const seen = new Set(), order = [];
    const walk = (name) => {
      if (seen.has(name)) return; seen.add(name); order.push(name);
      const pj = JSON.parse(fs.readFileSync(path.join(root, name, "package.json"), "utf8"));
      for (const d of Object.keys(pj.dependencies || {}).sort()) walk(d);
    };
    walk("@supabase/supabase-js");
    const out = [];
    for (const name of order) {
      const dir = path.join(root, name);
      const pj = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8"));
      const lic = fs.readdirSync(dir).find(f => /^licen[cs]e/i.test(f));
      out.push("=".repeat(72), `${name} ${pj.version} (${pj.license})`, "=".repeat(72),
               lic ? fs.readFileSync(path.join(dir, lic), "utf8").trim() : "(no licence file in the package)", "");
    }
    process.stdout.write(out.join("\n"));
  ' "$PKG" > "$1/LICENSES.txt"
}

if [ "$MODE" = "--check" ]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  build "$tmp"
  bad=0
  for f in supabase-js.js LICENSES.txt; do
    if ! cmp -s "$tmp/$f" "$OUT/$f"; then echo "  $OUT/$f does not match supabase-js $want" >&2; bad=1; fi
  done
  extra=$(ls "$OUT" | grep -vxE 'supabase-js\.js|LICENSES\.txt' || true)
  if [ -n "$extra" ]; then echo "  unexpected file(s) in $OUT: $extra" >&2; bad=1; fi
  if [ $bad -ne 0 ]; then
    echo "Vendored supabase-js is stale. Run: (cd web && npm ci) && bash scripts/vendor-supabase-js.sh, then commit web/vendor/." >&2
    exit 1
  fi
  echo "web/vendor matches @supabase/supabase-js $want (bundle sha256 $sum)."
  exit 0
fi

mkdir -p "$OUT"
build "$OUT"
echo "Wrote $OUT/supabase-js.js and $OUT/LICENSES.txt from @supabase/supabase-js $want (bundle sha256 $sum)."
