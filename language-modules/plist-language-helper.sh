plist_read_first_string_key() {
  local plist_file="$1"
  shift

  PLIST_FILE="$plist_file" python3 - "$@" <<'PY'
import os
import plistlib
import sys

path = os.environ["PLIST_FILE"]
keys = sys.argv[1:]

with open(path, "rb") as handle:
    data = plistlib.load(handle)

for key in keys:
    value = data.get(key)
    if isinstance(value, str) and value:
        print(value)
        raise SystemExit(0)

raise SystemExit(1)
PY
}

plist_write_string_keys() {
  local plist_file="$1"
  shift

  [ $(( $# % 2 )) -eq 0 ] || fail "plist_write_string_keys requires key/value pairs."

  PLIST_FILE="$plist_file" python3 - "$@" <<'PY'
import os
import plistlib
import sys

path = os.environ["PLIST_FILE"]
pairs = sys.argv[1:]

with open(path, "rb") as handle:
    data = plistlib.load(handle)

for index in range(0, len(pairs), 2):
    data[pairs[index]] = pairs[index + 1]

with open(path, "wb") as handle:
    plistlib.dump(data, handle, sort_keys=False)
PY
}
