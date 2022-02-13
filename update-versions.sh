#! /bin/bash
# LPGL v3 (c) 2022 MooreaTv <moorea@ymail.com>

# shellcheck source=interfaces.txt
source "$(dirname "${BASH_SOURCE[0]}")/interfaces.txt"

variants="BCC Classic Mainline"

for v in $variants; do
    echo "Toc for $v is ${!v}"
done

for v in $variants; do
    find . -type f -name "*-$v.toc" -print0 | xargs -0 -I % sh -c "echo 'Updating %'; sed -i -E -e \"s/## *Interface:.*/## Interface: ${!v}/i\" %"
done
