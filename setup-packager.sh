#!/usr/bin/env bash

# Install pandoc for WoWI changelog output ([md -> html] -> bbcode)
install_pandoc() {
	command -v pandoc &>/dev/null && return 0

	if [[ -n "$WOWI_API_TOKEN" && "$GITHUB_REF" == "refs/tags/"* && "$INPUT_PANDOC" == "true" ]]; then
		sudo apt-get install -yq pandoc &>/dev/null && echo -e "##[group]Install pandoc\\n[command]pandoc --version\\n$( pandoc --version )\\n##[endgroup]"
	fi
}

if [[ -n $GITHUB_ACTIONS ]]; then
	install_pandoc
fi
