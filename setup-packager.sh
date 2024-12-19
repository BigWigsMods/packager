#!/usr/bin/env bash

# Install pandoc for WoWI changelog output ([md -> html] -> bbcode)
install_pandoc() {
	command -v pandoc &>/dev/null && return 0

	if [[ -n "$WOWI_API_TOKEN" && "$GITHUB_REF" == "refs/tags/"* && "$INPUT_PANDOC" == "true" ]]; then
		sudo apt-get install -yq pandoc &>/dev/null && echo -e "##[group]Install pandoc\\n[command]pandoc --version\\n$( pandoc --version )\\n##[endgroup]"
	fi
}

# Install subversion if the pkgmeta includes external svn repos
install_subversion() {
	command -v svn &>/dev/null && return 0

	local pkgmeta_file
	local OPTIND
	while getopts ":m:" opt "$INPUT_ARGS"; do
		case $opt in
			m)
				pkgmeta_file="${GITHUB_WORKSPACE}/${OPTARG}"
				[[ ! -f "$pkgmeta_file" ]] && return 0
				;;
			*)
		esac
	done
	if [[ -z "$pkgmeta_file" ]]; then
		if [[ -f "${GITHUB_WORKSPACE}/.pkgmeta" ]]; then
			pkgmeta_file="${GITHUB_WORKSPACE}/.pkgmeta"
		elif [[ -f "${GITHUB_WORKSPACE}/pkgmeta.yaml" ]]; then
			pkgmeta_file="${GITHUB_WORKSPACE}/pkgmeta.yaml"
		else
			return 0
		fi
	fi

	# check type then url, exit 1 if no matches
	if yq -e '.externals | ( (.[] | select(.type == "svn")) or (with_entries(.value |= .url) | .[] | select(test(".*/trunk(?:/|$)"))) )' < "$pkgmeta_file" &>/dev/null; then
		# echo "::notice title=GitHub Actions Change::The runner image for ubuntu-latest is being updated to use ubuntu-24.04, which no longer includes subversion." \
		#      "Update your workflow \"run-as\" to use ubuntu-22.04 directly or add a step to install subversion to continue support for svn repositories."
		sudo apt-get install -yq subversion &>/dev/null && echo -e "##[group]Install subversion\\n[command]svn --version\\n$( svn --version )\\n##[endgroup]"
	fi
}

if [[ -n $GITHUB_ACTIONS ]]; then
	install_pandoc
	install_subversion
fi
