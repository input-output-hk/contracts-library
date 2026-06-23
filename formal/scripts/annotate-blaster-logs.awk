#!/usr/bin/awk -f
# Annotate `lake build` output: tag each `<file>.lean:<line>:<col>:` location
# with the nearest preceding `theorem|lemma|example|def <name>`, so messages
# from blaster (`✅ Valid`, `❌ Falsified`, ...) and `#import_uplc` identify the
# property being checked, not just the file.
#
# Usage (run from formal/, where lake reports paths relative to the package):
#   lake build 2>&1 | awk -f scripts/annotate-blaster-logs.awk
#
# Adapted from francolq/aiken-good-practices scripts/annotate-blaster-logs.awk;
# the reference prefixes paths with `verify/` because it runs lake from the
# parent dir. We run lake from formal/, so paths resolve as-is.
# Falls back to the original line if no name can be found.

{
  line = $0
  rest = line
  out = ""
  while (match(rest, /[A-Za-z0-9_./-]+\.lean:[0-9]+:[0-9]+:/)) {
    loc = substr(rest, RSTART, RLENGTH)
    out = out substr(rest, 1, RSTART - 1) loc
    rest = substr(rest, RSTART + RLENGTH)
    n = split(loc, parts, ":")
    file = parts[1]
    for (i = 2; i <= n - 3; i++) file = file ":" parts[i]
    lineno = parts[n - 2] + 0
    name = nameAt(file, lineno)
    if (name != "") out = out " [" name "]"
  }
  print out rest
}

function nameAt(file, lineno,    i, current, l, m) {
  if (!(file in cached)) {
    cached[file] = 1
    i = 0
    current = ""
    while ((getline l < file) > 0) {
      i++
      if (match(l, /^[[:space:]]*(private[[:space:]]+|protected[[:space:]]+)?(theorem|lemma|example|def|abbrev|instance)[[:space:]]+[A-Za-z_][A-Za-z0-9_'.]*/)) {
        m = substr(l, RSTART, RLENGTH)
        sub(/^[[:space:]]*(private[[:space:]]+|protected[[:space:]]+)?(theorem|lemma|example|def|abbrev|instance)[[:space:]]+/, "", m)
        current = m
      }
      nameByLine[file, i] = current
    }
    close(file)
    maxLine[file] = i
  }
  if (lineno > maxLine[file]) lineno = maxLine[file]
  return nameByLine[file, lineno]
}
