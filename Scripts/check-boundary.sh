#!/bin/sh
# Open-core boundary check: nothing from the commercial apps' backend,
# account or billing code may enter this repository.
# Exit status 1 if any banned term appears in tracked source or docs.
set -eu
cd "$(dirname "$0")/.."
found=0
for term in APIClient tier subscription; do
    if grep -rniw --include='*.swift' --include='*.md' --include='*.yml' --include='*.cff' \
        --exclude-dir=.build --exclude-dir=.swiftpm --exclude='check-boundary.sh' \
        -e "$term" . ; then
        echo "boundary check: found '$term'" >&2
        found=1
    fi
done
if grep -rn --include='*.swift' --exclude-dir=.build -e 'URLSession' -e 'http://' -e 'https://' Sources ; then
    echo "boundary check: network code in Sources" >&2
    found=1
fi
[ "$found" -eq 0 ] && echo "boundary check: clean"
exit "$found"
