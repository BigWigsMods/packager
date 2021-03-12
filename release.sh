#!/usr/bin/env bash

# release.sh generates an addon zip file from a Git, SVN, or Mercurial checkout.
#
# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <http://unlicense.org/>

## USER OPTIONS

# Secrets for uploading
cf_token=
github_token=
wowi_token=
wago_token=

# Variables set via command-line options
slug=
addonid=
wagoid=
topdir=
releasedir=
overwrite=
nolib=
line_ending="dos"
skip_copying=
skip_externals=
skip_localization=
skip_zipfile=
skip_upload=
skip_cf_upload=
pkgmeta_file=
file_type=

# Game versions for uploading
game_version=
game_version_id=
toc_version=
alpha=
classic=

## END USER OPTIONS


# Script return code
exit_code=0

# Process command-line options
usage() {
	echo "Usage: release.sh [-cdelLosuz] [-t topdir] [-r releasedir] [-p curse-id] [-w wowi-id] [-g game-version] [-m pkgmeta.yml]" >&2
	echo "  -c               Skip copying files into the package directory." >&2
	echo "  -d               Skip uploading." >&2
	echo "  -e               Skip checkout of external repositories." >&2
	echo "  -l               Skip @localization@ keyword replacement." >&2
	echo "  -L               Only do @localization@ keyword replacement (skip upload to CurseForge)." >&2
	echo "  -o               Keep existing package directory, overwriting its contents." >&2
	echo "  -s               Create a stripped-down \"nolib\" package." >&2
	echo "  -u               Use Unix line-endings." >&2
	echo "  -z               Skip zip file creation." >&2
	echo "  -t topdir        Set top-level directory of checkout." >&2
	echo "  -r releasedir    Set directory containing the package directory. Defaults to \"\$topdir/.release\"." >&2
	echo "  -p curse-id      Set the project id used on CurseForge for localization and uploading. (Use 0 to unset the TOC value)" >&2
	echo "  -w wowi-id       Set the addon id used on WoWInterface for uploading. (Use 0 to unset the TOC value)" >&2
	echo "  -a wago-id       Set the project id used on Wago Addons for uploading. (Use 0 to unset the TOC value)" >&2
	echo "  -g game-version  Set the game version to use for CurseForge uploading." >&2
	echo "  -m pkgmeta.yaml  Set the pkgmeta file to use." >&2
}

OPTIND=1
while getopts ":celLzusop:dw:a:r:t:g:m:" opt; do
	case $opt in
	c)
		# Skip copying files into the package directory.
		skip_copying="true"
		skip_upload="true"
		;;
	e)
		# Skip checkout of external repositories.
		skip_externals="true"
		;;
	l)
		# Skip @localization@ keyword replacement.
		skip_localization="true"
		;;
	L)
		# Skip uploading to CurseForge.
		skip_cf_upload="true"
		;;
	d)
		# Skip uploading.
		skip_upload="true"
		;;
	o)
		# Skip deleting any previous package directory.
		overwrite="true"
		;;
	p)
		slug="$OPTARG"
		;;
	w)
		addonid="$OPTARG"
		;;
	a)
		wagoid="$OPTARG"
		;;
	r)
		# Set the release directory to a non-default value.
		releasedir="$OPTARG"
		;;
	s)
		# Create a nolib package.
		nolib="true"
		skip_externals="true"
		;;
	t)
		# Set the top-level directory of the checkout to a non-default value.
		if [ ! -d "$OPTARG" ]; then
			echo "Invalid argument for option \"-t\" - Directory \"$OPTARG\" does not exist." >&2
			usage
			exit 1
		fi
		topdir="$OPTARG"
		;;
	u)
		# Skip Unix-to-DOS line-ending translation.
		line_ending=unix
		;;
	z)
		# Skip generating the zipfile.
		skip_zipfile="true"
		;;
	g)
		# shortcut for classic
		if [ "$OPTARG" = "classic" ]; then
			classic="true"
			# game_version from toc
		else
			# Set version (x.y.z)
			IFS=',' read -ra V <<< "$OPTARG"
			for i in "${V[@]}"; do
				if [[ ! "$i" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)[a-z]?$ ]]; then
					echo "Invalid argument for option \"-g\" ($i)" >&2
					usage
					exit 1
				fi
				if [[ ${BASH_REMATCH[1]} == "1" && ${BASH_REMATCH[2]} == "13" ]]; then
					classic="true"
					toc_version=$( printf "%d%02d%02d" ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} )
				fi
			done
			game_version="$OPTARG"
		fi
		;;
	m)
		# Set the pkgmeta file.
		if [ ! -f "$OPTARG" ]; then
			echo "Invalid argument for option \"-m\" - File \"$OPTARG\" does not exist." >&2
			usage
			exit 1
		fi
		pkgmeta_file="$OPTARG"
		;;
	:)
		echo "Option \"-$OPTARG\" requires an argument." >&2
		usage
		exit 1
		;;
	\?)
		if [ "$OPTARG" = "?" ] || [ "$OPTARG" = "h" ]; then
			usage
			exit 0
		fi
		echo "Unknown option \"-$OPTARG\"" >&2
		usage
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

# Set $topdir to top-level directory of the checkout.
if [ -z "$topdir" ]; then
	dir=$( pwd )
	if [ -d "$dir/.git" ] || [ -d "$dir/.svn" ] || [ -d "$dir/.hg" ]; then
		topdir=.
	else
		dir=${dir%/*}
		topdir=".."
		while [ -n "$dir" ]; do
			if [ -d "$topdir/.git" ] || [ -d "$topdir/.svn" ] || [ -d "$topdir/.hg" ]; then
				break
			fi
			dir=${dir%/*}
			topdir="$topdir/.."
		done
		if [ ! -d "$topdir/.git" ] && [ ! -d "$topdir/.svn" ] && [ ! -d "$topdir/.hg" ]; then
			echo "No Git, SVN, or Hg checkout found." >&2
			exit 1
		fi
	fi
fi

# Handle folding sections in CI logs
start_group() { echo "$1"; }
end_group() { echo; }

# Check for Travis CI
if [ -n "$TRAVIS" ]; then
	# Don't run the packager for pull requests
	if [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
		echo "Not packaging pull request."
		exit 0
	fi
	if [ -z "$TRAVIS_TAG" ]; then
		# Don't run the packager if there is a tag pending
		check_tag=$( git -C "$topdir" tag --points-at HEAD )
		if [ -n "$check_tag" ]; then
			echo "Found future tag \"${check_tag}\", not packaging."
			exit 0
		fi
		# Only package master, classic, or develop
		if [ "$TRAVIS_BRANCH" != "master" ] && [ "$TRAVIS_BRANCH" != "classic" ] && [ "$TRAVIS_BRANCH" != "develop" ]; then
			echo "Not packaging \"${TRAVIS_BRANCH}\"."
			exit 0
		fi
	fi
	# https://github.com/travis-ci/travis-build/tree/master/lib/travis/build/bash
	start_group() {
		echo -en "travis_fold:start:$2\\r\033[0K"
		# release_timer_id="$(printf %08x $((RANDOM * RANDOM)))"
		# release_timer_start_time="$(date -u +%s%N)"
		# echo -en "travis_time:start:${release_timer_id}\\r\033[0K"
		echo "$1"
	}
	end_group() {
		# local release_timer_end_time="$(date -u +%s%N)"
		# local duration=$((release_timer_end_time - release_timer_start_time))
		# echo -en "\\ntravis_time:end:${release_timer_id}:start=${release_timer_start_time},finish=${release_timer_end_time},duration=${duration}\\r\033[0K"
		echo -en "travis_fold:end:$1\\r\033[0K"
	}
fi

# Check for GitHub Actions
if [ -n "$GITHUB_ACTIONS" ]; then
	# Prevent duplicate builds
	if [[ "$GITHUB_REF" == "refs/heads"* ]]; then
		check_tag=$( git -C "$topdir" tag --points-at HEAD )
		if [ -n "$check_tag" ]; then
			echo "Found future tag \"${check_tag}\", not packaging."
			exit 0
		fi
	fi
	start_group() { echo "##[group]$1"; }
	end_group() { echo "##[endgroup]"; }
fi
unset check_tag

# Load secrets
if [ -f "$topdir/.env" ]; then
	# shellcheck disable=1090
	. "$topdir/.env"
elif [ -f ".env" ]; then
	. ".env"
fi
[ -z "$cf_token" ] && cf_token=$CF_API_KEY
[ -z "$github_token" ] && github_token=$GITHUB_OAUTH
[ -z "$wowi_token" ] && wowi_token=$WOWI_API_TOKEN
[ -z "$wago_token" ] && wago_token=$WAGO_API_TOKEN

# Set $releasedir to the directory which will contain the generated addon zipfile.
if [ -z "$releasedir" ]; then
	releasedir="$topdir/.release"
fi

# Set $basedir to the basename of the checkout directory.
basedir=$( cd "$topdir" && pwd )
case $basedir in
/*/*)
	basedir=${basedir##/*/}
	;;
/*)
	basedir=${basedir##/}
	;;
esac

# Set $repository_type to "git" or "svn" or "hg".
repository_type=
if [ -d "$topdir/.git" ]; then
	repository_type=git
elif [ -d "$topdir/.svn" ]; then
	repository_type=svn
elif [ -d "$topdir/.hg" ]; then
	repository_type=hg
else
	echo "No Git, SVN, or Hg checkout found in \"$topdir\"." >&2
	exit 1
fi

# $releasedir must be an absolute path or inside $topdir.
case $releasedir in
/*)			;;
$topdir/*)	;;
*)
	echo "The release directory \"$releasedir\" must be an absolute path or inside \"$topdir\"." >&2
	exit 1
	;;
esac

# Create the staging directory.
mkdir -p "$releasedir" 2>/dev/null || {
	echo "Unable to create the release directory \"$releasedir\"." >&2
	exit 1
}

# Expand $topdir and $releasedir to their absolute paths for string comparisons later.
topdir=$( cd "$topdir" && pwd )
releasedir=$( cd "$releasedir" && pwd )

###
### set_info_<repo> returns the following information:
###
si_repo_type= # "git" or "svn" or "hg"
si_repo_dir= # the checkout directory
si_repo_url= # the checkout url
si_tag= # tag for HEAD
si_previous_tag= # previous tag
si_previous_revision= # [SVN|Hg] revision number for previous tag

si_project_revision= # Turns into the highest revision of the entire project in integer form, e.g. 1234, for SVN. Turns into the commit count for the project's hash for Git.
si_project_hash= # [Git|Hg] Turns into the hash of the entire project in hex form. e.g. 106c634df4b3dd4691bf24e148a23e9af35165ea
si_project_abbreviated_hash= # [Git|Hg] Turns into the abbreviated hash of the entire project in hex form. e.g. 106c63f
si_project_author= # Turns into the last author of the entire project. e.g. ckknight
si_project_date_iso= # Turns into the last changed date (by UTC) of the entire project in ISO 8601. e.g. 2008-05-01T12:34:56Z
si_project_date_integer= # Turns into the last changed date (by UTC) of the entire project in a readable integer fashion. e.g. 2008050123456
si_project_timestamp= # Turns into the last changed date (by UTC) of the entire project in POSIX timestamp. e.g. 1209663296
si_project_version= # Turns into an approximate version of the project. The tag name if on a tag, otherwise it's up to the repo. SVN returns something like "r1234", Git returns something like "v0.1-873fc1"

si_file_revision= # Turns into the current revision of the file in integer form, e.g. 1234, for SVN. Turns into the commit count for the file's hash for Git.
si_file_hash= # Turns into the hash of the file in hex form. e.g. 106c634df4b3dd4691bf24e148a23e9af35165ea
si_file_abbreviated_hash= # Turns into the abbreviated hash of the file in hex form. e.g. 106c63
si_file_author= # Turns into the last author of the file. e.g. ckknight
si_file_date_iso= # Turns into the last changed date (by UTC) of the file in ISO 8601. e.g. 2008-05-01T12:34:56Z
si_file_date_integer= # Turns into the last changed date (by UTC) of the file in a readable integer fashion. e.g. 20080501123456
si_file_timestamp= # Turns into the last changed date (by UTC) of the file in POSIX timestamp. e.g. 1209663296

# SVN date helper function
strtotime() {
	local value="$1" # datetime string
	local format="$2" # strptime string
	if [[ "${OSTYPE,,}" == *"darwin"* ]]; then # bsd
		date -j -f "$format" "$value" "+%s" 2>/dev/null
	else # gnu
		date -d "$value" +%s 2>/dev/null
	fi
}

set_info_git() {
	si_repo_dir="$1"
	si_repo_type="git"
	si_repo_url=$( git -C "$si_repo_dir" remote get-url origin 2>/dev/null | sed -e 's/^git@\(.*\):/https:\/\/\1\//' )
	if [ -z "$si_repo_url" ]; then # no origin so grab the first fetch url
		si_repo_url=$( git -C "$si_repo_dir" remote -v | awk '/(fetch)/ { print $2; exit }' | sed -e 's/^git@\(.*\):/https:\/\/\1\//' )
	fi

	# Populate filter vars.
	si_project_hash=$( git -C "$si_repo_dir" show --no-patch --format="%H" 2>/dev/null )
	si_project_abbreviated_hash=$( git -C "$si_repo_dir" show --no-patch --abbrev=7 --format="%h" 2>/dev/null )
	si_project_author=$( git -C "$si_repo_dir" show --no-patch --format="%an" 2>/dev/null )
	si_project_timestamp=$( git -C "$si_repo_dir" show --no-patch --format="%at" 2>/dev/null )
	si_project_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_project_timestamp" )
	si_project_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_project_timestamp" )
	# XXX --depth limits rev-list :\ [ ! -s "$(git rev-parse --git-dir)/shallow" ] || git fetch --unshallow --no-tags
	si_project_revision=$( git -C "$si_repo_dir" rev-list --count "$si_project_hash" 2>/dev/null )

	# Get the tag for the HEAD.
	si_previous_tag=
	si_previous_revision=
	_si_tag=$( git -C "$si_repo_dir" describe --tags --always --abbrev=7 2>/dev/null )
	si_tag=$( git -C "$si_repo_dir" describe --tags --always --abbrev=0 2>/dev/null )
	# Set $si_project_version to the version number of HEAD. May be empty if there are no commits.
	si_project_version=$si_tag
	# The HEAD is not tagged if the HEAD is several commits past the most recent tag.
	if [ "$si_tag" = "$si_project_hash" ]; then
		# --abbrev=0 expands out the full sha if there was no previous tag
		si_project_version=$_si_tag
		si_previous_tag=
		si_tag=
	elif [ "$_si_tag" != "$si_tag" ]; then
		# not on a tag
		si_project_version=$( git -C "$si_repo_dir" describe --tags --abbrev=7 --exclude="*alpha*" 2>/dev/null )
		si_previous_tag=$( git -C "$si_repo_dir" describe --tags --abbrev=0 --exclude="*alpha*" 2>/dev/null )
		si_tag=
	else # we're on a tag, just jump back one commit
		if [[ $si_tag != *"beta"* && $si_tag != *"alpha"* ]]; then
			# full release, ignore beta tags
			si_previous_tag=$( git -C "$si_repo_dir" describe --tags --abbrev=0 --exclude="*alpha*" --exclude="*beta*" HEAD~ 2>/dev/null )
		else
			si_previous_tag=$( git -C "$si_repo_dir" describe --tags --abbrev=0 --exclude="*alpha*" HEAD~ 2>/dev/null )
		fi
	fi
}

set_info_svn() {
	si_repo_dir="$1"
	si_repo_type="svn"

	# Temporary file to hold results of "svn info".
	_si_svninfo="${si_repo_dir}/.svn/release_sh_svninfo"
	svn info -r BASE "$si_repo_dir" 2>/dev/null > "$_si_svninfo"

	if [ -s "$_si_svninfo" ]; then
		_si_root=$( awk '/^Repository Root:/ { print $3; exit }' < "$_si_svninfo" )
		_si_url=$( awk '/^URL:/ { print $2; exit }' < "$_si_svninfo" )
		_si_revision=$( awk '/^Last Changed Rev:/ { print $NF; exit }' < "$_si_svninfo" )
		si_repo_url=$_si_root

		case ${_si_url#${_si_root}/} in
		tags/*)
			# Extract the tag from the URL.
			si_tag=${_si_url#${_si_root}/tags/}
			si_tag=${si_tag%%/*}
			si_project_revision="$_si_revision"
			;;
		*)
			# Check if the latest tag matches the working copy revision (/trunk checkout instead of /tags)
			_si_tag_line=$( svn log --verbose --limit 1 "$_si_root/tags" 2>/dev/null | awk '/^   A/ { print $0; exit }' )
			_si_tag=$( echo "$_si_tag_line" | awk '/^   A/ { print $2 }' | awk -F/ '{ print $NF }' )
			_si_tag_from_revision=$( echo "$_si_tag_line" | sed -e 's/^.*:\([0-9]\{1,\}\)).*$/\1/' ) # (from /project/trunk:N)

			if [ "$_si_tag_from_revision" = "$_si_revision" ]; then
				si_tag="$_si_tag"
				si_project_revision=$( svn info "$_si_root/tags/$si_tag" 2>/dev/null | awk '/^Last Changed Rev:/ { print $NF; exit }' )
			else
				# Set $si_project_revision to the highest revision of the project at the checkout path
				si_project_revision=$( svn info --recursive "$si_repo_dir" 2>/dev/null | awk '/^Last Changed Rev:/ { print $NF }' | sort -nr | head -n1 )
			fi
			;;
		esac

		if [ -n "$si_tag" ]; then
			si_project_version="$si_tag"
		else
			si_project_version="r$si_project_revision"
		fi

		# Get the previous tag and it's revision
		_si_limit=$((si_project_revision - 1))
		_si_tag=$( svn log --verbose --limit 1 "$_si_root/tags" -r $_si_limit:1 2>/dev/null | awk '/^   A/ { print $0; exit }' | awk '/^   A/ { print $2 }' | awk -F/ '{ print $NF }' )
		if [ -n "$_si_tag" ]; then
			si_previous_tag="$_si_tag"
			si_previous_revision=$( svn info "$_si_root/tags/$_si_tag" 2>/dev/null | awk '/^Last Changed Rev:/ { print $NF; exit }' )
		fi

		# Populate filter vars.
		si_project_author=$( awk '/^Last Changed Author:/ { print $0; exit }' < "$_si_svninfo" | cut -d" " -f4- )
		_si_timestamp=$( awk '/^Last Changed Date:/ { print $4,$5; exit }' < "$_si_svninfo" )
		si_project_timestamp=$( strtotime "$_si_timestamp" "%F %T" )
		si_project_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_project_timestamp" )
		si_project_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_project_timestamp" )
		# SVN repositories have no project hash.
		si_project_hash=
		si_project_abbreviated_hash=

		rm -f "$_si_svninfo" 2>/dev/null
	fi
}

set_info_hg() {
	si_repo_dir="$1"
	si_repo_type="hg"
	si_repo_url=$( hg --cwd "$si_repo_dir" paths -q default )
	if [ -z "$si_repo_url" ]; then # no default so grab the first path
		si_repo_url=$( hg --cwd "$si_repo_dir" paths | awk '{ print $3; exit }' )
	fi

	# Populate filter vars.
	si_project_hash=$( hg --cwd "$si_repo_dir" log -r . --template '{node}' 2>/dev/null )
	si_project_abbreviated_hash=$( hg --cwd "$si_repo_dir" log -r . --template '{node|short}' 2>/dev/null )
	si_project_author=$( hg --cwd "$si_repo_dir" log -r . --template '{author}' 2>/dev/null )
	si_project_timestamp=$( hg --cwd "$si_repo_dir" log -r . --template '{date}' 2>/dev/null | cut -d. -f1 )
	si_project_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_project_timestamp" )
	si_project_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_project_timestamp" )
	si_project_revision=$( hg --cwd "$si_repo_dir" log -r . --template '{rev}' 2>/dev/null )

	# Get tag info
	si_tag=
	# I'm just muddling through revsets, so there is probably a better way to do this
	# Ignore tag commits, so v1.0-1 will package as v1.0
	if [ "$( hg --cwd "$si_repo_dir" log -r '.-filelog(.hgtags)' --template '{rev}' 2>/dev/null )" == "" ]; then
		_si_tip=$( hg --cwd "$si_repo_dir" log -r 'last(parents(.))' --template '{rev}' 2>/dev/null )
	else
		_si_tip=$( hg --cwd "$si_repo_dir" log -r . --template '{rev}' 2>/dev/null )
	fi
	si_previous_tag=$( hg --cwd "$si_repo_dir" log -r "$_si_tip" --template '{latesttag}' 2>/dev/null )
	# si_project_version=$( hg --cwd "$si_repo_dir" log -r "$_si_tip" --template "{ ifeq(changessincelatesttag, 0, latesttag, '{latesttag}-{changessincelatesttag}-m{node|short}') }" 2>/dev/null ) # git style
	si_project_version=$( hg --cwd "$si_repo_dir" log -r "$_si_tip" --template "{ ifeq(changessincelatesttag, 0, latesttag, 'r{rev}') }" 2>/dev/null ) # svn style
	if [ "$si_previous_tag" = "$si_project_version" ]; then
		# we're on a tag
		si_tag=$si_previous_tag
		si_previous_tag=$( hg --cwd "$si_repo_dir" log -r "last(parents($_si_tip))" --template '{latesttag}' 2>/dev/null )
	fi
	si_previous_revision=$( hg --cwd "$si_repo_dir" log -r "$si_previous_tag" --template '{rev}' 2>/dev/null )
}

set_info_file() {
	if [ "$si_repo_type" = "git" ]; then
		_si_file=${1#si_repo_dir} # need the path relative to the checkout
		# Populate filter vars from the last commit the file was included in.
		si_file_hash=$( git -C "$si_repo_dir" log --max-count=1 --format="%H" "$_si_file" 2>/dev/null )
		si_file_abbreviated_hash=$( git -C "$si_repo_dir" log --max-count=1 --abbrev=7 --format="%h" "$_si_file" 2>/dev/null )
		si_file_author=$( git -C "$si_repo_dir" log --max-count=1 --format="%an" "$_si_file" 2>/dev/null )
		si_file_timestamp=$( git -C "$si_repo_dir" log --max-count=1 --format="%at" "$_si_file" 2>/dev/null )
		si_file_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_file_timestamp" )
		si_file_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_file_timestamp" )
		si_file_revision=$( git -C "$si_repo_dir" rev-list --count "$si_file_hash" 2>/dev/null ) # XXX checkout depth affects rev-list, see set_info_git
	elif [ "$si_repo_type" = "svn" ]; then
		_si_file="$1"
		# Temporary file to hold results of "svn info".
		_sif_svninfo="${si_repo_dir}/.svn/release_sh_svnfinfo"
		svn info "$_si_file" 2>/dev/null > "$_sif_svninfo"
		if [ -s "$_sif_svninfo" ]; then
			# Populate filter vars.
			si_file_revision=$( awk '/^Last Changed Rev:/ { print $NF; exit }' < "$_sif_svninfo" )
			si_file_author=$( awk '/^Last Changed Author:/ { print $0; exit }' < "$_sif_svninfo" | cut -d" " -f4- )
			_si_timestamp=$( awk '/^Last Changed Date:/ { print $4,$5,$6; exit }' < "$_sif_svninfo" )
			si_file_timestamp=$( strtotime "$_si_timestamp" "%F %T %z" )
			si_file_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_file_timestamp" )
			si_file_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_file_timestamp" )
			# SVN repositories have no project hash.
			si_file_hash=
			si_file_abbreviated_hash=

			rm -f "$_sif_svninfo" 2>/dev/null
		fi
	elif [ "$si_repo_type" = "hg" ]; then
		_si_file=${1#si_repo_dir} # need the path relative to the checkout
		# Populate filter vars.
		si_file_hash=$( hg --cwd "$si_repo_dir" log --limit 1 --template '{node}' "$_si_file" 2>/dev/null )
		si_file_abbreviated_hash=$( hg --cwd "$si_repo_dir" log --limit 1 --template '{node|short}' "$_si_file" 2>/dev/null )
		si_file_author=$( hg --cwd "$si_repo_dir" log --limit 1 --template '{author}' "$_si_file" 2>/dev/null )
		si_file_timestamp=$( hg --cwd "$si_repo_dir" log --limit 1 --template '{date}' "$_si_file" 2>/dev/null | cut -d. -f1 )
		si_file_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_file_timestamp" )
		si_file_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_file_timestamp" )
		si_file_revision=$( hg --cwd "$si_repo_dir" log --limit 1 --template '{rev}' "$_si_file" 2>/dev/null )
	fi
}

# Set some version info about the project
case $repository_type in
git)	set_info_git "$topdir" ;;
svn)	set_info_svn "$topdir" ;;
hg) 	set_info_hg  "$topdir" ;;
esac

tag=$si_tag
project_version=$si_project_version
previous_version=$si_previous_tag
project_hash=$si_project_hash
project_revision=$si_project_revision
previous_revision=$si_previous_revision
project_timestamp=$si_project_timestamp
project_github_url=
project_github_slug=
if [[ "$si_repo_url" == "https://github.com"* ]]; then
	project_github_url=${si_repo_url%.git}
	project_github_slug=${project_github_url#https://github.com/}
fi
project_site=

# Bare carriage-return character.
carriage_return=$( printf "\r" )

# Returns 0 if $1 matches one of the colon-separated patterns in $2.
match_pattern() {
	_mp_file=$1
	_mp_list="$2:"
	while [ -n "$_mp_list" ]; do
		_mp_pattern=${_mp_list%%:*}
		_mp_list=${_mp_list#*:}
		# shellcheck disable=2254
		case $_mp_file in
			$_mp_pattern)
				return 0
				;;
		esac
	done
	return 1
}

# Simple .pkgmeta YAML processor.
yaml_keyvalue() {
	yaml_key=${1%%:*}
	yaml_value=${1#$yaml_key:}
	yaml_value=${yaml_value#"${yaml_value%%[! ]*}"} # trim leading whitespace
	yaml_value=${yaml_value#[\'\"]} # trim leading quotes
	yaml_value=${yaml_value%[\'\"]} # trim trailing quotes
}

yaml_listitem() {
	yaml_item=${1#-}
	yaml_item=${yaml_item#"${yaml_item%%[! ]*}"} # trim leading whitespace
}

###
### Process .pkgmeta to set variables used later in the script.
###

if [ -z "$pkgmeta_file" ]; then
	pkgmeta_file="$topdir/.pkgmeta"
	# CurseForge allows this so check for it
	if [ ! -f "$pkgmeta_file" ] && [ -f "$topdir/pkgmeta.yaml" ]; then
		pkgmeta_file="$topdir/pkgmeta.yaml"
	fi
fi

# Variables set via .pkgmeta.
package=
manual_changelog=
changelog=
changelog_markup="text"
enable_nolib_creation=
ignore=
contents=
nolib_exclude=
wowi_gen_changelog="true"
wowi_archive="true"
wowi_convert_changelog="true"
declare -A relations=()

parse_ignore() {
	pkgmeta="$1"
	[ -f "$pkgmeta" ] || return 1

	checkpath="$topdir" # paths are relative to the topdir
	copypath=""
	if [ "$2" != "" ]; then
		checkpath=$( dirname "$pkgmeta" )
		copypath="$2/"
	fi

	yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof="true"
		# Skip commented out lines.
		if [[ $yaml_line =~ ^[[:space:]]*\# ]]; then
			continue
		fi
		# Strip any trailing CR character.
		yaml_line=${yaml_line%$carriage_return}

		case $yaml_line in
		[!\ ]*:*)
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key
			;;
		[\ ]*"- "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"} # trim leading whitespace
			# Get the YAML list item.
			yaml_listitem "$yaml_line"
			if [ "$pkgmeta_phase" = "ignore" ]; then
				pattern=$yaml_item
				if [ -d "$checkpath/$pattern" ]; then
					pattern="$copypath$pattern/*"
				elif [ ! -f "$checkpath/$pattern" ]; then
					# doesn't exist so match both a file and a path
					pattern="$copypath$pattern:$copypath$pattern/*"
				else
					pattern="$copypath$pattern"
				fi
				if [ -z "$ignore" ]; then
					ignore="$pattern"
				else
					ignore="$ignore:$pattern"
				fi
			fi
			;;
		esac
	done < "$pkgmeta"
}

if [ -f "$pkgmeta_file" ]; then
	if grep -q --max-count=1 $'^[ ]*\t\+[[:blank:]]*[[:graph:]]' "$pkgmeta_file"; then
		# Try to cut down on some troubleshooting pain.
		echo "ERROR! Your pkgmeta file contains a leading tab. Only spaces are allowed for indentation in YAML files." >&2
		grep --line-number $'^[ ]*\t\+[[:blank:]]*[[:graph:]]' "$pkgmeta_file" | sed 's/\t/^I/g'
		exit 1
	fi

	yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof="true"
		# Skip commented out lines.
		if [[ $yaml_line =~ ^[[:space:]]*\# ]]; then
			continue
		fi
		# Strip any trailing CR character.
		yaml_line=${yaml_line%$carriage_return}

		case $yaml_line in
		[!\ ]*:*)
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key

			case $yaml_key in
			enable-nolib-creation)
				if [ "$yaml_value" = "yes" ]; then
					enable_nolib_creation="true"
				fi
				;;
			manual-changelog)
				changelog=$yaml_value
				manual_changelog="true"
				;;
			changelog-title)
				project="$yaml_value"
				;;
			package-as)
				package=$yaml_value
				;;
			wowi-create-changelog)
				if [ "$yaml_value" = "no" ]; then
					wowi_gen_changelog=
				fi
				;;
			wowi-convert-changelog)
				if [ "$yaml_value" = "no" ]; then
					wowi_convert_changelog=
				fi
				;;
			wowi-archive-previous)
				if [ "$yaml_value" = "no" ]; then
					wowi_archive=
				fi
				;;
			esac
			;;
		" "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"} # trim leading whitespace
			case $yaml_line in
			"- "*)
				# Get the YAML list item.
				yaml_listitem "$yaml_line"
				case $pkgmeta_phase in
				ignore)
					pattern=$yaml_item
					if [ -d "$topdir/$pattern" ]; then
						pattern="$pattern/*"
					elif [ ! -f "$topdir/$pattern" ]; then
						# doesn't exist so match both a file and a path
						pattern="$pattern:$pattern/*"
					fi
					if [ -z "$ignore" ]; then
						ignore="$pattern"
					else
						ignore="$ignore:$pattern"
					fi
					;;
				tools-used)
					relations["$yaml_item"]="tool"
					;;
				required-dependencies)
					relations["$yaml_item"]="requiredDependency"
					;;
				optional-dependencies)
					relations["$yaml_item"]="optionalDependency"
					;;
				embedded-libraries)
					relations["$yaml_item"]="embeddedLibrary"
					;;
				esac
				;;
			*:*)
				# Split $yaml_line into a $yaml_key, $yaml_value pair.
				yaml_keyvalue "$yaml_line"
				case $pkgmeta_phase in
				manual-changelog)
					case $yaml_key in
					filename)
						changelog=$yaml_value
						manual_changelog="true"
						;;
					markup-type)
						if [ "$yaml_value" = "markdown" ] || [ "$yaml_value" = "html" ]; then
							changelog_markup=$yaml_value
						else
							changelog_markup="text"
						fi
						;;
					esac
					;;
				esac
				;;
			esac
			;;
		esac
	done < "$pkgmeta_file"
fi

# Add untracked/ignored files to the ignore list
if [ "$repository_type" = "git" ]; then
	OLDIFS=$IFS
	IFS=$'\n'
	for _vcs_ignore in $(git -C "$topdir" ls-files --others --directory); do
		if [ -d "$topdir/$_vcs_ignore" ]; then
			_vcs_ignore="$_vcs_ignore*"
		fi
		if [ -z "$ignore" ]; then
			ignore="$_vcs_ignore"
		else
			ignore="$ignore:$_vcs_ignore"
		fi
	done
	IFS=$OLDIFS
elif [ "$repository_type" = "svn" ]; then
	# svn always being difficult.
	OLDIFS=$IFS
	IFS=$'\n'
	for _vcs_ignore in $( cd "$topdir" && svn status --no-ignore --ignore-externals | awk '/^[?IX]/' | cut -c9- | tr '\\' '/' ); do
		if [ -d "$topdir/$_vcs_ignore" ]; then
			_vcs_ignore="$_vcs_ignore/*"
		fi
		if [ -z "$ignore" ]; then
			ignore="$_vcs_ignore"
		else
			ignore="$ignore:$_vcs_ignore"
		fi
	done
	IFS=$OLDIFS
elif [ "$repository_type" = "hg" ]; then
	_vcs_ignore=$( hg --cwd "$topdir" status --ignored --unknown --no-status --print0 | tr '\0' ':' )
	if [ -n "$_vcs_ignore" ]; then
		_vcs_ignore=${_vcs_ignore:0:-1}
		if [ -z "$ignore" ]; then
			ignore="$_vcs_ignore"
		else
			ignore="$ignore:$_vcs_ignore"
		fi
	fi
fi

# TOC file processing.
tocfile=$(
	cd "$topdir" || exit
	filename=$( ls ./*.toc -1 2>/dev/null | head -n1 )
	if [[ -z "$filename" && -n "$package" ]]; then
		# Handle having the core addon in a sub dir, which people have starting doing
		# for some reason. Tons of caveats, just make the base dir your base addon people!
		filename=$( ls "$package"/*.toc -1 2>/dev/null | head -n1 )
	fi
	echo "$filename"
)
if [[ -z "$tocfile" || ! -f "$topdir/$tocfile" ]]; then
	echo "Could not find an addon TOC file. In another directory? Make sure it matches the 'package-as' in .pkgmeta" >&2
	exit 1
fi

# Set the package name from the TOC filename.
toc_name=$( basename "$tocfile" | sed 's/\.toc$//' )
if [[ -n "$package" && "$package" != "$toc_name" ]]; then
	echo "Addon package name does not match TOC file name." >&2
	exit 1
fi
if [ -z "$package" ]; then
	package="$toc_name"
fi

# Get the interface version for setting upload version.
toc_file=$( sed -e $'1s/^\xEF\xBB\xBF//' -e $'s/\r//g' "$topdir/$tocfile" ) # go away bom, crlf
if [ -n "$classic" ] && [ -z "$toc_version" ] && [ -z "$game_version" ]; then
	toc_version=$( echo "$toc_file" | awk '/## Interface:[[:space:]]*113/ { print $NF; exit }' )
fi
if [ -z "$toc_version" ]; then
	toc_version=$( echo "$toc_file" | awk '/^## Interface:/ { print $NF; exit }' )
	if [[ "$toc_version" == "113"* ]]; then
		classic="true"
	fi
fi
if [ -z "$game_version" ]; then
	game_version="${toc_version:0:1}.$( printf "%d" ${toc_version:1:2} ).$( printf "%d" ${toc_version:3:2} )"
fi

# Get the title of the project for using in the changelog.
if [ -z "$project" ]; then
	project=$( echo "$toc_file" | awk '/^## Title:/ { print $0; exit }' | sed -e 's/|c[0-9A-Fa-f]\{8\}//g' -e 's/|r//g' -e 's/|T[^|]*|t//g' -e 's/## Title[[:space:]]*:[[:space:]]*\(.*\)/\1/' -e 's/[[:space:]]*$//' )
fi
# Grab CurseForge ID and WoWI ID from the TOC file if not set by the script.
if [ -z "$slug" ]; then
	slug=$( echo "$toc_file" | awk '/^## X-Curse-Project-ID:/ { print $NF; exit }' )
fi
if [ -z "$addonid" ]; then
	addonid=$( echo "$toc_file" | awk '/^## X-WoWI-ID:/ { print $NF; exit }' )
fi
if [ -z "$wagoid" ]; then
	wagoid=$( echo "$toc_file" | awk '/^## X-Wago-ID:/ { print $NF; exit }' )
fi
unset toc_file

# unset project ids if they are set to 0
[ "$slug" = "0" ] && slug=
[ "$addonid" = "0" ] && addonid=
[ "$wagoid" = "0" ] && wagoid=

# Automatic file type detection based on CurseForge rules
# 1) Untagged commits will be marked as an alpha.
# 2) Tagged commits will be marked as a release with the following exceptions:
#    - If the tag contains the word "alpha", it will be marked as an alpha file.
#    - If instead the tag contains the word "beta", it will be marked as a beta file.
if [ -n "$tag" ]; then
	if [[ "${tag,,}" == *"alpha"* ]]; then
		file_type="alpha"
	elif [[ "${tag,,}" == *"beta"* ]]; then
		file_type="beta"
	else
		file_type="release"
	fi
else
	file_type="alpha"
fi

echo
echo "Packaging $package"
if [ -n "$project_version" ]; then
	echo "Current version: $project_version"
fi
if [ -n "$previous_version" ]; then
	echo "Previous version: $previous_version"
fi
(
	[ -n "$classic" ] && retail="non-retail" || retail="retail"
	[ "$file_type" = "alpha" ] && alpha="alpha" || alpha="non-alpha"
	echo "Build type: ${retail} ${alpha} non-debug${nolib:+ nolib}"
	echo "Game version: ${game_version}"
	echo
)
if [[ "$slug" =~ ^[0-9]+$ ]]; then
	project_site="https://wow.curseforge.com"
	echo "CurseForge ID: $slug${cf_token:+ [token set]}"
fi
if [ -n "$addonid" ]; then
	echo "WoWInterface ID: $addonid${wowi_token:+ [token set]}"
fi
if [ -n "$wagoid" ]; then
	echo "Wago ID: $wagoid${wago_token:+ [token set]}"
fi
if [ -n "$project_github_slug" ]; then
	echo "GitHub: $project_github_slug${github_token:+ [token set]}"
fi
if [ -n "$project_site" ] || [ -n "$addonid" ] || [ -n "$project_github_slug" ]; then
	echo
fi
echo "Checkout directory: $topdir"
echo "Release directory: $releasedir"
echo

# Set $pkgdir to the path of the package directory inside $releasedir.
pkgdir="$releasedir/$package"
if [ -d "$pkgdir" ] && [ -z "$overwrite" ]; then
	#echo "Removing previous package directory: $pkgdir"
	rm -fr "$pkgdir"
fi
if [ ! -d "$pkgdir" ]; then
	mkdir -p "$pkgdir"
fi

# Set the contents of the addon zipfile.
contents="$package"

###
### Create filters for pass-through processing of files to replace repository keywords.
###

# Escape a string for use in sed substitutions.
escape_substr() {
	local s="$1"
	s=${s//\\/\\\\}
	s=${s//\//\\/}
	s=${s//&/\\&}
	echo "$s"
}

# Filter for simple repository keyword replacement.
vcs_filter() {
	sed \
		-e "s/@project-revision@/$si_project_revision/g" \
		-e "s/@project-hash@/$si_project_hash/g" \
		-e "s/@project-abbreviated-hash@/$si_project_abbreviated_hash/g" \
		-e "s/@project-author@/$( escape_substr "$si_project_author" )/g" \
		-e "s/@project-date-iso@/$si_project_date_iso/g" \
		-e "s/@project-date-integer@/$si_project_date_integer/g" \
		-e "s/@project-timestamp@/$si_project_timestamp/g" \
		-e "s/@project-version@/$( escape_substr "$si_project_version" )/g" \
		-e "s/@file-revision@/$si_file_revision/g" \
		-e "s/@file-hash@/$si_file_hash/g" \
		-e "s/@file-abbreviated-hash@/$si_file_abbreviated_hash/g" \
		-e "s/@file-author@/$( escape_substr "$si_file_author" )/g" \
		-e "s/@file-date-iso@/$si_file_date_iso/g" \
		-e "s/@file-date-integer@/$si_file_date_integer/g" \
		-e "s/@file-timestamp@/$si_file_timestamp/g"
}

# Find URL of localization api.
set_localization_url() {
	localization_url=
	if [ -n "$slug" ] && [ -n "$cf_token" ] && [ -n "$project_site" ]; then
		localization_url="${project_site}/api/projects/$slug/localization/export"
	fi
	if [ -z "$localization_url" ] && grep -rq --max-count=1 --include="*.lua" "@localization" "$topdir"; then
		echo "Skipping localization! Missing CurseForge API token and/or project id is invalid."
		echo
	fi
}

# Filter to handle @localization@ repository keyword replacement.
# https://authors.curseforge.com/knowledge-base/projects/531-localization-substitutions/
declare -A unlocalized_values=( ["english"]="ShowPrimary" ["comment"]="ShowPrimaryAsComment" ["blank"]="ShowBlankAsComment" ["ignore"]="Ignore" )
localization_filter() {
	_ul_eof=
	while [ -z "$_ul_eof" ]; do
		IFS='' read -r _ul_line || _ul_eof="true"
		# Strip any trailing CR character.
		_ul_line=${_ul_line%$carriage_return}
		case $_ul_line in
		*@localization\(*\)@*)
			_ul_lang=
			_ul_namespace=
			_ul_singlekey=
			_ul_tablename="L"
			# Get the prefix of the line before the comment.
			_ul_prefix=${_ul_line%%@localization(*}
			_ul_prefix=${_ul_prefix%%--*}
			# Strip everything but the localization parameters.
			_ul_params=${_ul_line#*@localization(}
			_ul_params=${_ul_params%)@}
			# Sanitize the params a bit. (namespaces are restricted to [a-zA-Z0-9_], separated by [./:])
			_ul_params=${_ul_params// /}
			_ul_params=${_ul_params//,/, }
			# Pull the locale language first (mainly for warnings).
			_ul_lang="enUS"
			if [[ $_ul_params == *"locale=\""* ]]; then
				_ul_lang=${_ul_params##*locale=\"}
				_ul_lang=${_ul_lang:0:4}
				_ul_lang=${_ul_lang%%\"*}
			else
				echo "    Warning! No locale set, using enUS." >&2
			fi
			# Generate a URL parameter string from the localization parameters.
			# https://authors.curseforge.com/knowledge-base/projects/529-api
			_ul_url_params=""
			set -- ${_ul_params}
			for _ul_param; do
				_ul_key=${_ul_param%%=*}
				_ul_value=${_ul_param#*=}
				_ul_value=${_ul_value%,*}
				_ul_value=${_ul_value#*\"}
				_ul_value=${_ul_value%\"*}
				case ${_ul_key} in
					escape-non-ascii)
						if [ "$_ul_value" = "true" ]; then
							_ul_url_params="${_ul_url_params}&escape-non-ascii-characters=true"
						fi
						;;
					format)
						if [ "$_ul_value" = "lua_table" ]; then
							_ul_url_params="${_ul_url_params}&export-type=Table"
						fi
						;;
					handle-unlocalized)
						if [ "$_ul_value" != "english" ] && [ -n "${unlocalized_values[$_ul_value]}" ]; then
							_ul_url_params="${_ul_url_params}&unlocalized=${unlocalized_values[$_ul_value]}"
						fi
						;;
					handle-subnamespaces)
						if [ "$_ul_value" = "concat" ]; then # concat with /
							_ul_url_params="${_ul_url_params}&concatenante-subnamespaces=true"
						elif [ "$_ul_value" = "subtable" ]; then
							echo "    ($_ul_lang) Warning! ${_ul_key}=\"${_ul_value}\" is not supported. Include each full subnamespace, comma delimited." >&2
						fi
						;;
					key)
						# _ul_params was stripped of spaces, so reparse the line for the key
						_ul_singlekey=${_ul_line#*@localization(}
						_ul_singlekey=${_ul_singlekey#*key=\"}
						_ul_singlekey=${_ul_singlekey%%\",*}
						_ul_singlekey=${_ul_singlekey%%\")@*}
						;;
					locale)
						_ul_lang=$_ul_value
						;;
					namespace)
						# reparse to get all namespaces if multiple
						_ul_namespace=${_ul_params##*namespace=\"}
						_ul_namespace=${_ul_namespace%%\"*}
						_ul_namespace=${_ul_namespace//, /,}
						_ul_url_params="${_ul_url_params}&namespaces=${_ul_namespace}"
						_ul_namespace="/${_ul_namespace}"
						;;
					namespace-delimiter)
						if [ "$_ul_value" != "/" ]; then
							echo "    ($_ul_lang) Warning! ${_ul_key}=\"${_ul_value}\" is not supported." >&2
						fi
						;;
					prefix-values)
						echo "    ($_ul_lang) Warning! \"${_ul_key}\" is not supported." >&2
						;;
					same-key-is-true)
						if [ "$_ul_value" = "true" ]; then
							_ul_url_params="${_ul_url_params}&true-if-value-equals-key=true"
						fi
						;;
					table-name)
						if [ "$_ul_value" != "L" ]; then
							_ul_tablename="$_ul_value"
							_ul_url_params="${_ul_url_params}&table-name=${_ul_value}"
						fi
						;;
				esac
			done

			if [ -z "$_cdt_localization" ] || [ -z "$localization_url" ]; then
				echo "    Skipping localization (${_ul_lang}${_ul_namespace})" >&2

				# If the line isn't a TOC entry, print anything before the keyword.
				if [[ $_ul_line != "## "* ]]; then
					if [ -n "$_ul_eof" ]; then
						echo -n "$_ul_prefix"
					else
						echo "$_ul_prefix"
					fi
				fi
			else
				_ul_url="${localization_url}?lang=${_ul_lang}${_ul_url_params}"
				echo "    Adding ${_ul_lang}${_ul_namespace}" >&2

				if [ -z "$_ul_singlekey" ]; then
					# Write text that preceded the substitution.
					echo -n "$_ul_prefix"

					# Fetch the localization data, but don't output anything if there is an error.
					curl -s -H "x-api-token: $cf_token" "${_ul_url}" | awk -v url="$_ul_url" '/^{"error/ { o="    Error! "$0"\n           "url; print o >"/dev/stderr"; exit 1 } /<!DOCTYPE/ { print "    Error! Invalid output\n           "url >"/dev/stderr"; exit 1 } /^'"$_ul_tablename"' = '"$_ul_tablename"' or \{\}/ { next } { print }'

					# Insert a trailing blank line to match CF packager.
					if [ -z "$_ul_eof" ]; then
						echo ""
					fi
				else
					# Parse out a single phrase. This is kind of expensive, but caching would be way too much effort to optimize for what is basically an edge case.
					_ul_value=$( curl -s -H "x-api-token: $cf_token" "${_ul_url}" | awk -v url="$_ul_url" '/^{"error/ { o="    Error! "$0"\n           "url; print o >"/dev/stderr"; exit 1 } /<!DOCTYPE/ { print "    Error! Invalid output\n           "url >"/dev/stderr"; exit 1 } { print }' | sed -n '/L\["'"$_ul_singlekey"'"\]/p' | sed 's/^.* = "\(.*\)"/\1/' )
					if [ -n "$_ul_value" ] && [ "$_ul_value" != "$_ul_singlekey" ]; then
						# The result is different from the base value so print out the line.
						echo "${_ul_prefix}${_ul_value}${_ul_line##*)@}"
					fi
				fi
			fi
			;;
		*)
			if [ -n "$_ul_eof" ]; then
				echo -n "$_ul_line"
			else
				echo "$_ul_line"
			fi
		esac
	done
}

lua_filter() {
	local level
	case $1 in
		alpha)  level="="    ;;
		debug)  level="=="   ;;
		retail) level="====" ;;
		*)      level="==="
	esac
	sed \
		-e "s/--@$1@/--[${level}[@$1@/g" \
		-e "s/--@end-$1@/--@end-$1@]${level}]/g" \
		-e "s/--\[===\[@non-$1@/--@non-$1@/g" \
		-e "s/--@end-non-$1@\]===\]/--@end-non-$1@/g"
}

toc_filter() {
	_trf_token=$1; shift
	_trf_comment=
	_trf_eof=
	while [ -z "$_trf_eof" ]; do
		IFS='' read -r _trf_line || _trf_eof="true"
		# Strip any trailing CR character.
		_trf_line=${_trf_line%$carriage_return}
		_trf_passthrough=
		case $_trf_line in
		"#@${_trf_token}@"*)
			_trf_comment="# "
			_trf_passthrough="true"
			;;
		"#@end-${_trf_token}@"*)
			_trf_comment=
			_trf_passthrough="true"
			;;
		esac
		if [ -z "$_trf_passthrough" ]; then
			_trf_line="$_trf_comment$_trf_line"
		fi
		if [ -n "$_trf_eof" ]; then
			echo -n "$_trf_line"
		else
			echo "$_trf_line"
		fi
	done
}

toc_filter2() {
	_trf_token=$1
	_trf_action=1
	if [ "$2" = "true" ]; then
		_trf_action=0
	fi
	shift 2
	_trf_keep=1
	_trf_uncomment=
	_trf_eof=
	while [ -z "$_trf_eof" ]; do
		IFS='' read -r _trf_line || _trf_eof="true"
		# Strip any trailing CR character.
		_trf_line=${_trf_line%$carriage_return}
		case $_trf_line in
		*"#@$_trf_token@"*)
			# remove the tokens, keep the content
			_trf_keep=$_trf_action
			;;
		*"#@non-$_trf_token@"*)
			# remove the tokens, remove the content
			_trf_keep=$(( 1-_trf_action ))
			_trf_uncomment="true"
			;;
		*"#@end-$_trf_token@"*|*"#@end-non-$_trf_token@"*)
			# remove the tokens
			_trf_keep=1
			_trf_uncomment=
			;;
		*)
			if (( _trf_keep )); then
				if [ -n "$_trf_uncomment" ]; then
					_trf_line="${_trf_line#\# }"
				fi
				if [ -n "$_trf_eof" ]; then
					echo -n "$_trf_line"
				else
					echo "$_trf_line"
				fi
			fi
			;;
		esac
	done
}

xml_filter() {
	sed \
		-e "s/<!--@$1@-->/<!--@$1/g" \
		-e "s/<!--@end-$1@-->/@end-$1@-->/g" \
		-e "s/<!--@non-$1@/<!--@non-$1@-->/g" \
		-e "s/@end-non-$1@-->/<!--@end-non-$1@-->/g"
}

do_not_package_filter() {
	_dnpf_token=$1; shift
	_dnpf_string="do-not-package"
	_dnpf_start_token=
	_dnpf_end_token=
	case $_dnpf_token in
	lua)
		_dnpf_start_token="--@$_dnpf_string@"
		_dnpf_end_token="--@end-$_dnpf_string@"
		;;
	toc)
		_dnpf_start_token="#@$_dnpf_string@"
		_dnpf_end_token="#@end-$_dnpf_string@"
		;;
	xml)
		_dnpf_start_token="<!--@$_dnpf_string@-->"
		_dnpf_end_token="<!--@end-$_dnpf_string@-->"
		;;
	esac
	if [ -z "$_dnpf_start_token" ] || [ -z "$_dnpf_end_token" ]; then
		cat
	else
		# Replace all content between the start and end tokens, inclusive, with a newline to match CF packager.
		_dnpf_eof=
		_dnpf_skip=
		while [ -z "$_dnpf_eof" ]; do
			IFS='' read -r _dnpf_line || _dnpf_eof="true"
			# Strip any trailing CR character.
			_dnpf_line=${_dnpf_line%$carriage_return}
			case $_dnpf_line in
			*$_dnpf_start_token*)
				_dnpf_skip="true"
				echo -n "${_dnpf_line%%${_dnpf_start_token}*}"
				;;
			*$_dnpf_end_token*)
				_dnpf_skip=
				if [ -z "$_dnpf_eof" ]; then
					echo ""
				fi
				;;
			*)
				if [ -z "$_dnpf_skip" ]; then
					if [ -n "$_dnpf_eof" ]; then
						echo -n "$_dnpf_line"
					else
						echo "$_dnpf_line"
					fi
				fi
				;;
			esac
		done
	fi
}

line_ending_filter() {
	_lef_eof=
	while [ -z "$_lef_eof" ]; do
		IFS='' read -r _lef_line || _lef_eof="true"
		# Strip any trailing CR character.
		_lef_line=${_lef_line%$carriage_return}
		if [ -n "$_lef_eof" ]; then
			# Preserve EOF not preceded by newlines.
			echo -n "$_lef_line"
		else
			case $line_ending in
			dos)
				# Terminate lines with CR LF.
				printf "%s\r\n" "$_lef_line"
				;;
			unix)
				# Terminate lines with LF.
				printf "%s\n" "$_lef_line"
				;;
			esac
		fi
	done
}

###
### Copy files from the working directory into the package directory.
###

# Copy of the contents of the source directory into the destination directory.
# Dotfiles and any files matching the ignore pattern are skipped.  Copied files
# are subject to repository keyword replacement.
#
copy_directory_tree() {
	_cdt_alpha=
	_cdt_debug=
	_cdt_ignored_patterns=
	_cdt_localization=
	_cdt_nolib=
	_cdt_do_not_package=
	_cdt_unchanged_patterns=
	_cdt_classic=
	OPTIND=1
	while getopts :adi:lnpu:c _cdt_opt "$@"; do
		# shellcheck disable=2220
		case $_cdt_opt in
			a)	_cdt_alpha="true" ;;
			d)	_cdt_debug="true" ;;
			i)	_cdt_ignored_patterns=$OPTARG ;;
			l)	_cdt_localization="true"
					set_localization_url
					;;
			n)	_cdt_nolib="true" ;;
			p)	_cdt_do_not_package="true" ;;
			u)	_cdt_unchanged_patterns=$OPTARG ;;
			c)	_cdt_classic="true" ;;
		esac
	done
	shift $((OPTIND - 1))
	_cdt_srcdir=$1
	_cdt_destdir=$2

	if [ -z "$_external_dir" ]; then
		start_group "Copying files into ${_cdt_destdir#$topdir/}:" "copy"
	else # don't nest groups
		echo "Copying files into ${_cdt_destdir#$topdir/}:"
	fi
	if [ ! -d "$_cdt_destdir" ]; then
		mkdir -p "$_cdt_destdir"
	fi
	# Create a "find" command to list all of the files in the current directory, minus any ones we need to prune.
	_cdt_find_cmd="find ."
	# Prune everything that begins with a dot except for the current directory ".".
	_cdt_find_cmd+=" \( -name \".*\" -a \! -name \".\" \) -prune"
	# Prune the destination directory if it is a subdirectory of the source directory.
	_cdt_dest_subdir=${_cdt_destdir#${_cdt_srcdir}/}
	case $_cdt_dest_subdir in
		/*)	;;
		*)	_cdt_find_cmd+=" -o -path \"./$_cdt_dest_subdir\" -prune" ;;
	esac
	# Print the filename, but suppress the current directory ".".
	_cdt_find_cmd+=" -o \! -name \".\" -print"
	( cd "$_cdt_srcdir" && eval "$_cdt_find_cmd" ) | while read -r file; do
		file=${file#./}
		if [ -f "$_cdt_srcdir/$file" ]; then
			# Check if the file should be ignored.
			skip_copy=
			# Prefix external files with the relative pkgdir path
			_cdt_check_file=$file
			if [ -n "${_cdt_destdir#$pkgdir}" ]; then
				_cdt_check_file="${_cdt_destdir#$pkgdir/}/$file"
			fi
			# Skip files matching the colon-separated "ignored" shell wildcard patterns.
			if [ -z "$skip_copy" ] && match_pattern "$_cdt_check_file" "$_cdt_ignored_patterns"; then
				skip_copy="true"
			fi
			# Never skip files that match the colon-separated "unchanged" shell wildcard patterns.
			unchanged=
			if [ -n "$skip_copy" ] && match_pattern "$file" "$_cdt_unchanged_patterns"; then
				skip_copy=
				unchanged="true"
			fi
			# Copy unskipped files into $_cdt_destdir.
			if [ -n "$skip_copy" ]; then
				echo "  Ignoring: $file"
			else
				dir=${file%/*}
				if [ "$dir" != "$file" ]; then
					mkdir -p "$_cdt_destdir/$dir"
				fi
				# Check if the file matches a pattern for keyword replacement.
				if [ -n "$unchanged" ] || ! match_pattern "$file" "*.lua:*.md:*.toc:*.txt:*.xml"; then
					echo "  Copying: $file (unchanged)"
					cp "$_cdt_srcdir/$file" "$_cdt_destdir/$dir"
				else
					# Set the filters for replacement based on file extension.
					_cdt_filters="vcs_filter"
					case $file in
						*.lua)
							[ -n "$_cdt_alpha" ] && _cdt_filters+="|lua_filter alpha"
							[ -n "$_cdt_debug" ] && _cdt_filters+="|lua_filter debug"
							[ -n "$_cdt_do_not_package" ] && _cdt_filters+="|do_not_package_filter lua"
							[ -n "$_cdt_classic" ] && _cdt_filters+="|lua_filter retail"
							[ -n "$_cdt_localization" ] && _cdt_filters+="|localization_filter"
							;;
						*.xml)
							[ -n "$_cdt_alpha" ] && _cdt_filters+="|xml_filter alpha"
							[ -n "$_cdt_debug" ] && _cdt_filters+="|xml_filter debug"
							[ -n "$_cdt_nolib" ] && _cdt_filters+="|xml_filter no-lib-strip"
							[ -n "$_cdt_do_not_package" ] && _cdt_filters+="|do_not_package_filter xml"
							[ -n "$_cdt_classic" ] && _cdt_filters+="|xml_filter retail"
							;;
						*.toc)
							_cdt_filters+="|toc_filter2 alpha ${_cdt_alpha:-0}"
							_cdt_filters+="|toc_filter2 debug ${_cdt_debug:-0}"
							_cdt_filters+="|toc_filter2 no-lib-strip ${_cdt_nolib:-0}"
							_cdt_filters+="|toc_filter2 do-not-package ${_cdt_do_not_package:-0}"
							_cdt_filters+="|toc_filter2 retail ${_cdt_classic:-0}"
							[ -n "$_cdt_localization" ] && _cdt_filters+="|localization_filter"
							;;
					esac

					# Set the filter for normalizing line endings.
					_cdt_filters+="|line_ending_filter"

					# Set version control values for the file.
					set_info_file "$_cdt_srcdir/$file"

					echo "  Copying: $file"
					eval < "$_cdt_srcdir/$file" "$_cdt_filters" > "$_cdt_destdir/$file"
				fi
			fi
		fi
	done
	if [ -z "$_external_dir" ]; then
		end_group "copy"
	fi
}

if [ -z "$skip_copying" ]; then
	cdt_args="-dp"
	[ "$file_type" != "alpha" ] && cdt_args+="a"
	[ -z "$skip_localization" ] && cdt_args+="l"
	[ -n "$nolib" ] && cdt_args+="n"
	[ -n "$classic" ] && cdt_args+="c"
	[ -n "$ignore" ] && cdt_args+=" -i \"$ignore\""
	[ -n "$changelog" ] && cdt_args+=" -u \"$changelog\""
	eval copy_directory_tree "$cdt_args" "\"$topdir\"" "\"$pkgdir\""
fi

# Reset ignore and parse pkgmeta ignores again to handle ignoring external paths
ignore=
parse_ignore "$pkgmeta_file"

###
### Process .pkgmeta again to perform any pre-move-folders actions.
###

retry() {
	local result=0
	local count=1
	while [[ "$count" -le 3 ]]; do
		[[ "$result" -ne 0 ]] && {
			echo -e "\033[01;31mRetrying (${count}/3)\033[0m" >&2
		}
		"$@" && { result=0 && break; } || result="$?"
		count="$((count + 1))"
		sleep 3
	done
	return "$result"
}

# Checkout the external into a ".checkout" subdirectory of the final directory.
checkout_external() {
	_external_dir=$1
	_external_uri=$2
	_external_tag=$3
	_external_type=$4
	# shellcheck disable=2034
	_external_slug=$5 # unused until we can easily fetch the project id
	_external_checkout_type=$6

	_cqe_checkout_dir="$pkgdir/$_external_dir/.checkout"
	mkdir -p "$_cqe_checkout_dir"
	if [ "$_external_type" = "git" ]; then
		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			retry git clone -q --depth 1 "$_external_uri" "$_cqe_checkout_dir" || return 1
		elif [ "$_external_tag" != "latest" ]; then
			echo "Fetching $_external_checkout_type \"$_external_tag\" from external $_external_uri"
			if [ "$_external_checkout_type" = "commit" ]; then
				retry git clone -q "$_external_uri" "$_cqe_checkout_dir" || return 1
				git -C "$_cqe_checkout_dir" checkout -q "$_external_tag" || return 1
			else
				git -c advice.detachedHead=false clone -q --depth 1 --branch "$_external_tag" "$_external_uri" "$_cqe_checkout_dir" || return 1
			fi
		else # [ "$_external_tag" = "latest" ]; then
			retry git clone -q --depth 50 "$_external_uri" "$_cqe_checkout_dir" || return 1
			_external_tag=$( git -C "$_cqe_checkout_dir" for-each-ref refs/tags --sort=-creatordate --format=%\(refname:short\) --count=1 )
			if [ -n "$_external_tag" ]; then
				echo "Fetching tag \"$_external_tag\" from external $_external_uri"
				git -C "$_cqe_checkout_dir" checkout -q "$_external_tag" || return 1
			else
				echo "Fetching latest version of external $_external_uri"
			fi
		fi

		# pull submodules
		git -C "$_cqe_checkout_dir" submodule -q update --init --recursive || return 1

		set_info_git "$_cqe_checkout_dir"
		echo "Checked out $( git -C "$_cqe_checkout_dir" describe --always --tags --abbrev=7 --long )" #$si_project_abbreviated_hash
	elif [ "$_external_type" = "svn" ]; then
		if [[ $external_uri == *"/trunk" ]]; then
			_cqe_svn_trunk_url=$_external_uri
			_cqe_svn_subdir=
		else
			_cqe_svn_trunk_url="${_external_uri%/trunk/*}/trunk"
			_cqe_svn_subdir=${_external_uri#${_cqe_svn_trunk_url}/}
		fi

		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			retry svn checkout -q "$_external_uri" "$_cqe_checkout_dir" || return 1
		else
			_cqe_svn_tag_url="${_cqe_svn_trunk_url%/trunk}/tags"
			if [ "$_external_tag" = "latest" ]; then
				_external_tag=$( svn log --verbose --limit 1 "$_cqe_svn_tag_url" 2>/dev/null | awk '/^   A \/tags\// { print $2; exit }' | awk -F/ '{ print $3 }' )
				if [ -z "$_external_tag" ]; then
					_external_tag="latest"
				fi
			fi
			if [ "$_external_tag" = "latest" ]; then
				echo "No tags found in $_cqe_svn_tag_url"
				echo "Fetching latest version of external $_external_uri"
				retry svn checkout -q "$_external_uri" "$_cqe_checkout_dir" || return 1
			else
				_cqe_external_uri="${_cqe_svn_tag_url}/$_external_tag"
				if [ -n "$_cqe_svn_subdir" ]; then
					_cqe_external_uri="${_cqe_external_uri}/$_cqe_svn_subdir"
				fi
				echo "Fetching tag \"$_external_tag\" from external $_cqe_external_uri"
				retry svn checkout -q "$_cqe_external_uri" "$_cqe_checkout_dir" || return 1
			fi
		fi
		set_info_svn "$_cqe_checkout_dir"
		echo "Checked out r$si_project_revision"
	elif [ "$_external_type" = "hg" ]; then
		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			retry hg clone -q "$_external_uri" "$_cqe_checkout_dir" || return 1
		elif [ "$_external_tag" != "latest" ]; then
			echo "Fetching $_external_checkout_type \"$_external_tag\" from external $_external_uri"
			retry hg clone -q --updaterev "$_external_tag" "$_external_uri" "$_cqe_checkout_dir" || return 1
		else # [ "$_external_tag" = "latest" ]; then
			retry hg clone -q "$_external_uri" "$_cqe_checkout_dir" || return 1
			_external_tag=$( hg --cwd "$_cqe_checkout_dir" log -r . --template '{latesttag}' )
			if [ -n "$_external_tag" ]; then
				echo "Fetching tag \"$_external_tag\" from external $_external_uri"
				hg --cwd "$_cqe_checkout_dir" update -q "$_external_tag"
			else
				echo "Fetching latest version of external $_external_uri"
			fi
		fi
		set_info_hg "$_cqe_checkout_dir"
		echo "Checked out r$si_project_revision"
	else
		echo "Unknown external: $_external_uri" >&2
		return 1
	fi
	# Copy the checkout into the proper external directory.
	(
		cd "$_cqe_checkout_dir" || return 1
		# Set the slug for external localization, if needed.
		# Note: We don't actually do localization since we need the project id and
		# the only way to convert slug->id would be to scrape the project page :\
		slug= #$_external_slug
		project_site=
		if [[ "$_external_uri" == *"wowace.com"* || "$_external_uri" == *"curseforge.com"* ]]; then
			project_site="https://wow.curseforge.com"
		fi
		# If a .pkgmeta file is present, process it for an "ignore" list.
		parse_ignore "$_cqe_checkout_dir/.pkgmeta" "$_external_dir"
		copy_directory_tree -dnp -i "$ignore" "$_cqe_checkout_dir" "$pkgdir/$_external_dir"
	)
	# Remove the ".checkout" subdirectory containing the full checkout.
	if [ -d "$_cqe_checkout_dir" ]; then
		rm -fr "$_cqe_checkout_dir"
	fi
}

external_pids=()

external_dir=
external_uri=
external_tag=
external_type=
external_slug=
external_checkout_type=
process_external() {
	if [ -n "$external_dir" ] && [ -n "$external_uri" ] && [ -z "$skip_externals" ]; then
		# convert old curse repo urls
		case $external_uri in
			*git.curseforge.com*|*git.wowace.com*)
				external_type="git"
				# git://git.curseforge.com/wow/$slug/mainline.git -> https://repos.curseforge.com/wow/$slug
				external_uri=${external_uri%/mainline.git}
				external_uri="https://repos${external_uri#*://git}"
				;;
			*svn.curseforge.com*|*svn.wowace.com*)
				external_type="svn"
				# svn://svn.curseforge.com/wow/$slug/mainline/trunk -> https://repos.curseforge.com/wow/$slug/trunk
				external_uri=${external_uri/\/mainline/}
				external_uri="https://repos${external_uri#*://svn}"
				;;
			*hg.curseforge.com*|*hg.wowace.com*)
				external_type="hg"
				# http://hg.curseforge.com/wow/$slug/mainline -> https://repos.curseforge.com/wow/$slug
				external_uri=${external_uri%/mainline}
				external_uri="https://repos${external_uri#*://hg}"
				;;
			svn:*)
				# just in case
				external_type="svn"
				;;
			*)
				if [ -z "$external_type" ]; then
					external_type="git"
				fi
				;;
		esac

		if [[ $external_uri == "https://repos.curseforge.com/wow/"* || $external_uri == "https://repos.wowace.com/wow/"* ]]; then
			if [ -z "$external_slug" ]; then
				external_slug=${external_uri#*/wow/}
				external_slug=${external_slug%%/*}
			fi

			# check if the repo is svn
			_svn_path=${external_uri#*/wow/$external_slug/}
			if [[ "$_svn_path" == "trunk"* ]]; then
				external_type="svn"
			elif [[ "$_svn_path" == "tags/"* ]]; then
				external_type="svn"
				# change the tag path into the trunk path and use the tag var so it gets logged as a tag
				external_tag=${_svn_path#tags/}
				external_tag=${external_tag%%/*}
				external_uri="${external_uri%/tags*}/trunk${_svn_path#tags/$external_tag}"
			fi
		fi

		if [ -n "$external_slug" ]; then
			relations["$external_slug"]="embeddedLibrary"
		fi

		echo "Fetching external: $external_dir"
		checkout_external "$external_dir" "$external_uri" "$external_tag" "$external_type" "$external_slug" "$external_checkout_type" &> "$releasedir/.$BASHPID.externalout" &
		external_pids+=($!)
	fi
	external_dir=
	external_uri=
	external_tag=
	external_type=
	external_slug=
	external_checkout_type=
}

# Don't leave extra files around if exited early
kill_externals() {
	rm -f "$releasedir"/.*.externalout
	kill 0
}
trap kill_externals INT

if [ -z "$skip_externals" ] && [ -f "$pkgmeta_file" ]; then
	yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof="true"
		# Skip commented out lines.
		if [[ $yaml_line =~ ^[[:space:]]*\# ]]; then
			continue
		fi
		# Strip any trailing CR character.
		yaml_line=${yaml_line%$carriage_return}

		case $yaml_line in
		[!\ ]*:*)
			# Started a new section, so checkout any queued externals.
			process_external
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key
			;;
		" "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"} # trim leading whitespace
			case $yaml_line in
			"- "*)
				;;
			*:*)
				# Split $yaml_line into a $yaml_key, $yaml_value pair.
				yaml_keyvalue "$yaml_line"
				case $pkgmeta_phase in
				externals)
					case $yaml_key in
					url) external_uri=$yaml_value ;;
					tag)
						external_tag=$yaml_value
						external_checkout_type=$yaml_key
						;;
					branch)
						external_tag=$yaml_value
						external_checkout_type=$yaml_key
						;;
					commit)
						external_tag=$yaml_value
						external_checkout_type=$yaml_key
						;;
					type) external_type=$yaml_value ;;
					curse-slug) external_slug=$yaml_value ;;
					*)
						# Started a new external, so checkout any queued externals.
						process_external

						external_dir=$yaml_key
						nolib_exclude="$nolib_exclude $pkgdir/$external_dir/*"
						if [ -n "$yaml_value" ]; then
							external_uri=$yaml_value
							# Immediately checkout this fully-specified external.
							process_external
						fi
						;;
					esac
					;;
				esac
				;;
			esac
			;;
		esac
	done < "$pkgmeta_file"
	# Reached end of file, so checkout any remaining queued externals.
	process_external

	if [ ${#external_pids[*]} -gt 0 ]; then
		echo
		echo "Waiting for externals to finish..."
		echo

		while [ ${#external_pids[*]} -gt 0 ]; do
			wait -n
			for i in ${!external_pids[*]}; do
				pid=${external_pids[i]}
				if ! kill -0 $pid 2>/dev/null; then
					_external_output="$releasedir/.$pid.externalout"
					if ! wait $pid; then
						_external_error=1
						# wrap each line with a bright red color code
						awk '{ printf "\033[01;31m%s\033[0m\n", $0 }' "$_external_output"
						echo
					else
						start_group "$( head -n1 "$_external_output" )" "external.$pid"
						tail -n+2 "$_external_output"
						end_group "external.$pid"
					fi
					rm -f "$_external_output" 2>/dev/null
					unset 'external_pids[i]'
				fi
			done
		done

		if [ -n "$_external_error" ]; then
			echo
			echo "There was an error fetching externals :(" >&2
			exit 1
		fi
	fi
fi

# Restore the signal handlers
trap - INT

###
### Create the changelog of commits since the previous release tag.
###

if [ -z "$project" ]; then
	project="$package"
fi

# Create a changelog in the package directory if the source directory does
# not contain a manual changelog.
if [ -n "$manual_changelog" ] && [ -f "$topdir/$changelog" ]; then
	start_group "Using manual changelog at $changelog" "changelog"
	head -n7 "$topdir/$changelog"
	[ "$( wc -l < "$topdir/$changelog" )" -gt 7 ] && echo "..."
	end_group "changelog"

	# Convert Markdown to BBCode (with HTML as an intermediary) for sending to WoWInterface
	# Requires pandoc (http://pandoc.org/)
	if [ "$changelog_markup" = "markdown" ] && [ -n "$wowi_convert_changelog" ] && hash pandoc &>/dev/null; then
		wowi_changelog="$releasedir/WOWI-$project_version-CHANGELOG.txt"
		pandoc -f commonmark -t html "$topdir/$changelog" | sed \
			-e 's/<\(\/\)\?\(b\|i\|u\)>/[\1\2]/g' \
			-e 's/<\(\/\)\?em>/[\1i]/g' \
			-e 's/<\(\/\)\?strong>/[\1b]/g' \
			-e 's/<ul[^>]*>/[list]/g' -e 's/<ol[^>]*>/[list="1"]/g' \
			-e 's/<\/[ou]l>/[\/list]\n/g' \
			-e 's/<li><p>/[*]/g' -e 's/<li>/[*]/g' -e 's/<\/p><\/li>//g' -e 's/<\/li>//g' \
			-e 's/\[\*\]\[ \] /[*]☐ /g' -e 's/\[\*\]\[[xX]\] /[*]☒ /g' \
			-e 's/<h1[^>]*>/[size="6"]/g' -e 's/<h2[^>]*>/[size="5"]/g' -e 's/<h3[^>]*>/[size="4"]/g' \
			-e 's/<h4[^>]*>/[size="3"]/g' -e 's/<h5[^>]*>/[size="3"]/g' -e 's/<h6[^>]*>/[size="3"]/g' \
			-e 's/<\/h[1-6]>/[\/size]\n/g' \
			-e 's/<blockquote>/[quote]/g' -e 's/<\/blockquote>/[\/quote]\n/g' \
			-e 's/<div class="sourceCode"[^>]*><pre class="sourceCode lua"><code class="sourceCode lua">/[highlight="lua"]/g' -e 's/<\/code><\/pre><\/div>/[\/highlight]\n/g' \
			-e 's/<pre><code>/[code]/g' -e 's/<\/code><\/pre>/[\/code]\n/g' \
			-e 's/<code>/[font="monospace"]/g' -e 's/<\/code>/[\/font]/g' \
			-e 's/<a href=\"\([^"]\+\)\"[^>]*>/[url="\1"]/g' -e 's/<\/a>/\[\/url]/g' \
			-e 's/<img src=\"\([^"]\+\)\"[^>]*>/[img]\1[\/img]/g' \
			-e 's/<hr \/>/_____________________________________________________________________________\n/g' \
			-e 's/<\/p>/\n/g' \
			-e '/^<[^>]\+>$/d' -e 's/<[^>]\+>//g' \
			-e 's/&quot;/"/g' \
			-e 's/&amp;/&/g' \
			-e 's/&lt;/</g' \
			-e 's/&gt;/>/g' \
			-e "s/&#39;/'/g" \
			| line_ending_filter > "$wowi_changelog"
	fi
else
	if [ -n "$manual_changelog" ]; then
		echo "Warning! Could not find a manual changelog at $topdir/$changelog"
		manual_changelog=
	fi
	changelog="CHANGELOG.md"
	changelog_markup="markdown"

	start_group "Generating changelog of commits into $changelog" "changelog"

	_changelog_range=
	if [ "$repository_type" = "git" ]; then
		changelog_url=
		changelog_version=
		changelog_previous="[Previous Releases](${project_github_url}/releases)"
		changelog_url_wowi=
		changelog_version_wowi=
		changelog_previous_wowi="[url=${project_github_url}/releases]Previous Releases[/url]"
		if [ -z "$previous_version" ] && [ -z "$tag" ]; then
			# no range, show all commits up to ours
			changelog_url="[Full Changelog](${project_github_url}/commits/${project_hash})"
			changelog_version="[${project_version}](${project_github_url}/tree/${project_hash})"
			changelog_url_wowi="[url=${project_github_url}/commits/${project_hash}]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/${project_hash}]${project_version}[/url]"
			_changelog_range="$project_hash"
		elif [ -z "$previous_version" ] && [ -n "$tag" ]; then
			# first tag, show all commits upto it
			changelog_url="[Full Changelog](${project_github_url}/commits/${tag})"
			changelog_version="[${project_version}](${project_github_url}/tree/${tag})"
			changelog_url_wowi="[url=${project_github_url}/commits/${tag}]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/${tag}]${project_version}[/url]"
			_changelog_range="$tag"
		elif [ -n "$previous_version" ] && [ -z "$tag" ]; then
			# compare between last tag and our commit
			changelog_url="[Full Changelog](${project_github_url}/compare/${previous_version}...${project_hash})"
			changelog_version="[$project_version](${project_github_url}/tree/${project_hash})"
			changelog_url_wowi="[url=${project_github_url}/compare/${previous_version}...${project_hash}]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/${project_hash}]${project_version}[/url]"
			_changelog_range="$previous_version..$project_hash"
		elif [ -n "$previous_version" ] && [ -n "$tag" ]; then
			# compare between last tag and our tag
			changelog_url="[Full Changelog](${project_github_url}/compare/${previous_version}...${tag})"
			changelog_version="[$project_version](${project_github_url}/tree/${tag})"
			changelog_url_wowi="[url=${project_github_url}/compare/${previous_version}...${tag}]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/${tag}]${project_version}[/url]"
			_changelog_range="$previous_version..$tag"
		fi
		# lazy way out
		if [ -z "$project_github_url" ]; then
			changelog_url=
			changelog_version=$project_version
			changelog_previous=
			changelog_url_wowi=
			changelog_version_wowi="[color=orange]${project_version}[/color]"
			changelog_previous_wowi=
		elif [ -z "$github_token" ]; then
			# not creating releases :(
			changelog_previous=
			changelog_previous_wowi=
		fi
		changelog_date=$( TZ='' printf "%(%Y-%m-%d)T" "$project_timestamp" )

		cat <<- EOF | line_ending_filter > "$pkgdir/$changelog"
		# $project

		## $changelog_version ($changelog_date)
		$changelog_url $changelog_previous

		EOF
		git -C "$topdir" log "$_changelog_range" --pretty=format:"###%B" \
			| sed -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/- /g' -e 's/$/  /' \
			      -e 's/\([a-zA-Z0-9]\)_\([a-zA-Z0-9]\)/\1\\_\2/g' \
			      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
			      -e '/git-svn-id:/d' -e '/^[[:space:]]*This reverts commit [0-9a-f]\{40\}\.[[:space:]]*$/d' \
			      -e '/^[[:space:]]*$/d' \
			| line_ending_filter >> "$pkgdir/$changelog"

		# WoWI uses BBCode, generate something usable to post to the site
		# the file is deleted on successful upload
		if [ -n "$addonid" ] && [ -n "$tag" ] && [ -n "$wowi_gen_changelog" ]; then
			wowi_changelog="$releasedir/WOWI-$project_version-CHANGELOG.txt"
			cat <<- EOF | line_ending_filter > "$wowi_changelog"
			[size=5]${project}[/size]
			[size=4]${changelog_version_wowi} (${changelog_date})[/size]
			${changelog_url_wowi} ${changelog_previous_wowi}
			[list]
			EOF
			git -C "$topdir" log "$_changelog_range" --pretty=format:"###%B" \
				| sed -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/[*]/g' \
				      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
				      -e '/git-svn-id:/d' -e '/^[[:space:]]*This reverts commit [0-9a-f]\{40\}\.[[:space:]]*$/d' \
				      -e '/^[[:space:]]*$/d' \
				| line_ending_filter >> "$wowi_changelog"
			echo "[/list]" | line_ending_filter >> "$wowi_changelog"
		fi

	elif [ "$repository_type" = "svn" ]; then
		if [ -n "$previous_revision" ]; then
			_changelog_range="-r$project_revision:$previous_revision"
		else
			_changelog_range="-rHEAD:1"
		fi
		changelog_date=$( TZ='' printf "%(%Y-%m-%d)T" "$project_timestamp" )

		cat <<- EOF | line_ending_filter > "$pkgdir/$changelog"
		# $project

		## $project_version ($changelog_date)

		EOF
		svn log "$topdir" "$_changelog_range" --xml \
			| awk '/<msg>/,/<\/msg>/' \
			| sed -e 's/<msg>/###/g' -e 's/<\/msg>//g' \
			      -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/- /g' -e 's/$/  /' \
			      -e 's/\([a-zA-Z0-9]\)_\([a-zA-Z0-9]\)/\1\\_\2/g' \
			      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
			      -e '/^[[:space:]]*$/d' \
			| line_ending_filter >> "$pkgdir/$changelog"

		# WoWI uses BBCode, generate something usable to post to the site
		# the file is deleted on successful upload
		if [ -n "$addonid" ] && [ -n "$tag" ] && [ -n "$wowi_gen_changelog" ]; then
			wowi_changelog="$releasedir/WOWI-$project_version-CHANGELOG.txt"
			cat <<- EOF | line_ending_filter > "$wowi_changelog"
			[size=5]${project}[/size]
			[size=4][color=orange]${project_version}[/color] (${changelog_date})[/size]

			[list]
			EOF
			svn log "$topdir" "$_changelog_range" --xml \
				| awk '/<msg>/,/<\/msg>/' \
				| sed -e 's/<msg>/###/g' -e 's/<\/msg>//g' \
				      -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/[*]/g' \
				      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
				      -e '/^[[:space:]]*$/d' \
				| line_ending_filter >> "$wowi_changelog"
			echo "[/list]" | line_ending_filter >> "$wowi_changelog"
		fi

	elif [ "$repository_type" = "hg" ]; then
		if [ -n "$previous_revision" ]; then
			_changelog_range="::$project_revision - ::$previous_revision - filelog(.hgtags)"
		else
			_changelog_range="."
		fi
		changelog_date=$( TZ='' printf "%(%Y-%m-%d)T" "$project_timestamp" )

		cat <<- EOF | line_ending_filter > "$pkgdir/$changelog"
		# $project

		## $project_version ($changelog_date)

		EOF
		hg --cwd "$topdir" log -r "$_changelog_range" --template '- {fill(desc|strip, 76, "", "  ")}\n' | line_ending_filter >> "$pkgdir/$changelog"

		# WoWI uses BBCode, generate something usable to post to the site
		# the file is deleted on successful upload
		if [ -n "$addonid" ] && [ -n "$tag" ] && [ -n "$wowi_gen_changelog" ]; then
			wowi_changelog="$releasedir/WOWI-$project_version-CHANGELOG.txt"
			cat <<- EOF | line_ending_filter > "$wowi_changelog"
			[size=5]${project}[/size]
			[size=4][color=orange]${project_version}[/color] (${changelog_date})[/size]

			[list]
			EOF
			hg --cwd "$topdir" log "$_changelog_range" --template '[*]{desc|strip|escape}\n' | line_ending_filter >> "$wowi_changelog"
			echo "[/list]" | line_ending_filter >> "$wowi_changelog"
		fi
	fi

	echo "$(<"$pkgdir/$changelog")"
	end_group "changelog"
fi

###
### Process .pkgmeta to perform move-folders actions.
###

if [ -f "$pkgmeta_file" ]; then
	yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof="true"
		# Skip commented out lines.
		if [[ $yaml_line =~ ^[[:space:]]*\# ]]; then
			continue
		fi
		# Strip any trailing CR character.
		yaml_line=${yaml_line%$carriage_return}

		case $yaml_line in
		[!\ ]*:*)
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key
			;;
		" "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"} # trim leading whitespace
			case $yaml_line in
			"- "*)
				;;
			*:*)
				# Split $yaml_line into a $yaml_key, $yaml_value pair.
				yaml_keyvalue "$yaml_line"
				case $pkgmeta_phase in
				move-folders)
					srcdir="$releasedir/$yaml_key"
					destdir="$releasedir/$yaml_value"
					if [[ -d "$destdir" && -z "$overwrite" && "$srcdir" != "$destdir/"* ]]; then
						rm -fr "$destdir"
					fi
					if [ -d "$srcdir" ]; then
						if [ ! -d "$destdir" ]; then
							mkdir -p "$destdir"
						fi
						echo "Moving $yaml_key to $yaml_value"
						mv -f "$srcdir"/* "$destdir" && rm -fr "$srcdir"
						contents="$contents $yaml_value"
						# Check to see if the base source directory is empty
						_mf_basedir=${srcdir%$(basename "$yaml_key")}
						if [ ! "$( ls -A "$_mf_basedir" )" ]; then
							echo "Removing empty directory ${_mf_basedir#$releasedir/}"
							rm -fr "$_mf_basedir"
						fi
					fi
					# update external dir
					nolib_exclude=${nolib_exclude//$srcdir/$destdir}
					;;
				esac
				;;
			esac
			;;
		esac
	done < "$pkgmeta_file"
	if [ -n "$srcdir" ]; then
		echo
	fi
fi

###
### Create the final zipfile for the addon.
###

if [ -z "$skip_zipfile" ]; then
	archive_package_name="${package//[^A-Za-z0-9._-]/_}"

	classic_tag=
	if [[ -n "$classic" && "${project_version,,}" != *"classic"* ]]; then
		# if it's a classic build, and classic isn't in the name, append it for clarity
		classic_tag="-classic"
	fi

	archive_version="$project_version"
	archive_name="$archive_package_name-$project_version$classic_tag.zip"
	archive="$releasedir/$archive_name"

	nolib_archive_version="$project_version-nolib"
	nolib_archive_name="$archive_package_name-$nolib_archive_version$classic_tag.zip"
	nolib_archive="$releasedir/$nolib_archive_name"

	if [ -n "$nolib" ]; then
		archive_version="$nolib_archive_version"
		archive_name="$nolib_archive_name"
		archive="$nolib_archive"
		nolib_archive=
	fi

	start_group "Creating archive: $archive_name" "archive"
	if [ -f "$archive" ]; then
		rm -f "$archive"
	fi
	( cd "$releasedir" && zip -X -r "$archive" $contents )

	if [ ! -f "$archive" ]; then
		exit 1
	fi
	end_group "archive"

	# Create nolib version of the zipfile
	if [ -n "$enable_nolib_creation" ] && [ -z "$nolib" ] && [ -n "$nolib_exclude" ]; then
		# run the nolib_filter
		find "$pkgdir" -type f \( -name "*.xml" -o -name "*.toc" \) -print | while read -r file; do
			case $file in
			*.toc)	_filter="toc_filter2 no-lib-strip" ;;
			*.xml)	_filter="xml_filter no-lib-strip" ;;
			esac
			$_filter < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
		done

		# make the exclude paths relative to the release directory
		nolib_exclude=${nolib_exclude//$releasedir\//}

		start_group "Creating no-lib archive: $nolib_archive_name" "archive.nolib"
		if [ -f "$nolib_archive" ]; then
			rm -f "$nolib_archive"
		fi
		# set noglob so each nolib_exclude path gets quoted instead of expanded
		( set -f; cd "$releasedir" && zip -X -r -q "$nolib_archive" $contents -x $nolib_exclude )

		if [ ! -f "$nolib_archive" ]; then
			exit_code=1
		fi
		end_group "archive.nolib"
	fi

	###
	### Deploy the zipfile.
	###

	upload_curseforge=$( [[ -z "$skip_upload" && -z "$skip_cf_upload" && -n "$slug" && -n "$cf_token" && -n "$project_site" ]] && echo true )
	upload_wowinterface=$( [[ -z "$skip_upload" && -n "$tag" && -n "$addonid" && -n "$wowi_token" ]] && echo true )
	upload_wago=$( [[ -z "$skip_upload" && -n "$wagoid" && -n "$wago_token" ]] && echo true )
	upload_github=$( [[ -z "$skip_upload" && -n "$tag" && -n "$project_github_slug" && -n "$github_token" ]] && echo true )

	if [[ -n "$upload_curseforge" || -n "$upload_wowinterface" || -n "$upload_github" || -n "$upload_wago" ]] && ! hash jq &>/dev/null; then
		echo "Skipping upload because \"jq\" was not found."
		echo
		upload_curseforge=
		upload_wowinterface=
		upload_wago=
		upload_github=
		exit_code=1
	fi

	if [ -n "$upload_curseforge" ]; then
		_cf_versions=$( curl -s -H "x-api-token: $cf_token" $project_site/api/game/versions )
		if [ -n "$_cf_versions" ]; then
			if [ -n "$game_version" ]; then
				game_version_id=$(
					_v=
					IFS=',' read -ra V <<< "$game_version"
					for i in "${V[@]}"; do
						_v="$_v,\"$i\""
					done
					_v="[${_v#,}]"
					# jq -c '["8.0.1","7.3.5"] as $v | map(select(.name as $x | $v | index($x)) | .id)'
					echo "$_cf_versions" | jq -c --argjson v "$_v" 'map(select(.name as $x | $v | index($x)) | .id) | select(length > 0)' 2>/dev/null
				)
				if [ -n "$game_version_id" ]; then
					# and now the reverse, since an invalid version will just be dropped
					game_version=$( echo "$_cf_versions" | jq -r --argjson v "$game_version_id" 'map(select(.id as $x | $v | index($x)) | .name) | join(",")' 2>/dev/null )
				fi
			fi
			if [ -z "$game_version_id" ]; then
				if [ -n "$classic" ]; then
					game_version_type_id=67408
				else
					game_version_type_id=517
				fi
				game_version_id=$( echo "$_cf_versions" | jq -c --argjson v "$game_version_type_id" 'map(select(.gameVersionTypeID == $v)) | max_by(.id) | [.id]' 2>/dev/null )
				game_version=$( echo "$_cf_versions" | jq -r --argjson v "$game_version_type_id" 'map(select(.gameVersionTypeID == $v)) | max_by(.id) | .name' 2>/dev/null )
			fi
		fi
		if [ -z "$game_version_id" ]; then
			echo "Error fetching game version info from $project_site/api/game/versions"
			echo
			echo "Skipping upload to CurseForge."
			echo
			upload_curseforge=
			exit_code=1
		fi
	fi

	# Upload to CurseForge.
	if [ -n "$upload_curseforge" ]; then
		_cf_payload=$( cat <<-EOF
		{
		  "displayName": "$project_version$classic_tag",
		  "gameVersions": $game_version_id,
		  "releaseType": "$file_type",
		  "changelog": $( jq --slurp --raw-input '.' < "$pkgdir/$changelog" ),
		  "changelogType": "$changelog_markup"
		}
		EOF
		)
		_cf_payload_relations=
		for i in "${!relations[@]}"; do
			_cf_payload_relations="$_cf_payload_relations{\"slug\":\"$i\",\"type\":\"${relations[$i]}\"},"
		done
		if [[ -n $_cf_payload_relations ]]; then
			_cf_payload_relations="{\"relations\":{\"projects\":[${_cf_payload_relations%,}]}}"
			_cf_payload=$( echo "$_cf_payload $_cf_payload_relations" | jq -s -c '.[0] * .[1]' )
		fi

		echo "Uploading $archive_name ($game_version $file_type) to $project_site/projects/$slug"
		resultfile="$releasedir/cf_result.json"
		result=$( echo "$_cf_payload" | curl -sS --retry 3 --retry-delay 10 \
				-w "%{http_code}" -o "$resultfile" \
				-H "x-api-token: $cf_token" \
				-F "metadata=<-" \
				-F "file=@$archive" \
				"$project_site/api/projects/$slug/upload-file" ) &&
		{
			case $result in
				200) echo "Success!" ;;
				302)
					echo "Error! ($result)"
					# don't need to ouput the redirect page
					exit_code=1
					;;
				404)
					echo "Error! No project for \"$slug\" found."
					exit_code=1
					;;
				*)
					echo "Error! ($result)"
					if [ -s "$resultfile" ]; then
						echo "$(<"$resultfile")"
					fi
					exit_code=1
					;;
			esac
		} || {
			exit_code=1
		}
		echo

		rm -f "$resultfile" 2>/dev/null
	fi

	if [ -n "$upload_wowinterface" ]; then
		_wowi_versions=$( curl -s -H "x-api-token: $wowi_token" https://api.wowinterface.com/addons/compatible.json )
		if [ -n "$_wowi_versions" ]; then
			game_version=$( echo "$_wowi_versions" | jq -r '.[] | select(.interface == "'"$toc_version"'" and .default == true) | .id' 2>/dev/null )
			if [ -z "$game_version" ]; then
				game_version=$( echo "$_wowi_versions" | jq -r 'map(select(.interface == "'"$toc_version"'"))[0] | .id // empty' 2>/dev/null )
			fi
			# handle delayed support from WoWI
			if [ -z "$game_version" ] && [ -n "$classic" ]; then
				game_version=$( echo "$_wowi_versions" | jq -r '.[] | select(.interface == "'$((toc_version - 1))'") | .id' 2>/dev/null )
			fi
			if [ -z "$game_version" ]; then
				game_version=$( echo "$_wowi_versions" | jq -r '.[] | select(.default == true) | .id' 2>/dev/null )
			fi
		fi
		if [ -z "$game_version" ]; then
			echo "Error fetching game version info from https://api.wowinterface.com/addons/compatible.json"
			echo
			echo "Skipping upload to WoWInterface."
			echo
			upload_wowinterface=
			exit_code=1
		fi
	fi

	# Upload tags to WoWInterface.
	if [ -n "$upload_wowinterface" ]; then
		_wowi_args=()
		if [ -f "$wowi_changelog" ]; then
			_wowi_args+=("-F changelog=<$wowi_changelog")
		elif [ -n "$manual_changelog" ]; then
			_wowi_args+=("-F changelog=<$pkgdir/$changelog")
		fi
		if [ -z "$wowi_archive" ]; then
			_wowi_args+=("-F archive=No")
		fi

		echo "Uploading $archive_name ($game_version) to https://www.wowinterface.com/downloads/info$addonid"
		resultfile="$releasedir/wi_result.json"
		result=$( curl -sS --retry 3 --retry-delay 10 \
			  -w "%{http_code}" -o "$resultfile" \
			  -H "x-api-token: $wowi_token" \
			  -F "id=$addonid" \
			  -F "version=$archive_version" \
			  -F "compatible=$game_version" \
			  "${_wowi_args[@]}" \
			  -F "updatefile=@$archive" \
			  "https://api.wowinterface.com/addons/update" ) &&
		{
			case $result in
				202)
					echo "Success!"
					rm -f "$wowi_changelog" 2>/dev/null
					;;
				401)
					echo "Error! No addon for id \"$addonid\" found or you do not have permission to upload files."
					exit_code=1
					;;
				403)
					echo "Error! Incorrect api key or you do not have permission to upload files."
					exit_code=1
					;;
				*)
					echo "Error! ($result)"
					if [ -s "$resultfile" ]; then
						echo "$(<"$resultfile")"
					fi
					exit_code=1
					;;
			esac
		} || {
			exit_code=1
		}
		echo

		rm -f "$resultfile" 2>/dev/null
	fi

	# Upload to Wago
	if [ -n "$upload_wago" ] ; then
		_wago_support_property="supported_retail_patch"
		if [ -n "$classic" ]; then
			_wago_support_property="supported_classic_patch"
		fi

		_wago_stability=$file_type
		if [ "$file_type" = "release" ]; then
			_wago_stability="stable"
		fi

		_wago_payload=$( cat <<-EOF
		{
		  "label": "$project_version$classic_tag",
		  "$_wago_support_property": "$game_version",
		  "stability": "$_wago_stability",
		  "changelog": $( jq --slurp --raw-input '.' < "$pkgdir/$changelog" )
		}
		EOF
		)

		echo "Uploading $archive_name ($game_version $file_type) to Wago"
		resultfile="$releasedir/wago_result.json"
		result=$( echo "$_wago_payload" | curl -sS --retry 3 --retry-delay 10 \
				-w "%{http_code}" -o "$resultfile" \
				-H "authorization: Bearer $wago_token" \
				-H "accept: application/json" \
				-F "metadata=<-" \
				-F "file=@$archive" \
				"https://addons.wago.io/api/projects/$wagoid/version" ) &&
		{
			case $result in
				200|201) echo "Success!" ;;
				302)
					echo "Error! ($result)"
					# don't need to ouput the redirect page
					exit_code=1
					;;
				404)
					echo "Error! No Wago project for id \"$wagoid\" found."
					exit_code=1
					;;
				*)
					echo "Error! ($result)"
					if [ -s "$resultfile" ]; then
						echo "$(<"$resultfile")"
					fi
					exit_code=1
					;;
			esac
		} || {
			exit_code=1
		}
		echo

		rm -f "$resultfile" 2>/dev/null
	fi

	# Create a GitHub Release for tags and upload the zipfile as an asset.
	if [ -n "$upload_github" ]; then
		upload_github_asset() {
			_ghf_release_id=$1
			_ghf_file_name=$2
			_ghf_file_path=$3
			_ghf_resultfile="$releasedir/gh_asset_result.json"

			# check if an asset exists and delete it (editing a release)
			asset_id=$( curl -sS -H "Authorization: token $github_token" "https://api.github.com/repos/$project_github_slug/releases/$_ghf_release_id/assets" | jq '.[] | select(.name? == "'"$_ghf_file_name"'") | .id' )
			if [ -n "$asset_id" ]; then
				curl -s -H "Authorization: token $github_token" -X DELETE "https://api.github.com/repos/$project_github_slug/releases/assets/$asset_id" &>/dev/null
			fi

			echo -n "Uploading $_ghf_file_name... "
			result=$( curl -sS --retry 3 --retry-delay 10 \
					-w "%{http_code}" -o "$_ghf_resultfile" \
					-H "Authorization: token $github_token" \
					-H "Content-Type: application/zip" \
					--data-binary "@$_ghf_file_path" \
					"https://uploads.github.com/repos/$project_github_slug/releases/$_ghf_release_id/assets?name=$_ghf_file_name" ) &&
			{
				if [ "$result" = "201" ]; then
					echo "Success!"
				else
					echo "Error ($result)"
					if [ -s "$_ghf_resultfile" ]; then
						echo "$(<"$_ghf_resultfile")"
					fi
					exit_code=1
				fi
			} || {
				exit_code=1
			}

			rm -f "$_ghf_resultfile" 2>/dev/null
			return 0
		}

		_gh_payload=$( cat <<-EOF
		{
		  "tag_name": "$tag",
		  "name": "$tag",
		  "body": $( jq --slurp --raw-input '.' < "$pkgdir/$changelog" ),
		  "draft": false,
		  "prerelease": $( [[ "${tag,,}" == *"beta"* || "${tag,,}" == *"alpha"* ]] && echo true || echo false )
		}
		EOF
		)
		resultfile="$releasedir/gh_result.json"

		release_id=$( curl -sS -H "Authorization: token $github_token" "https://api.github.com/repos/$project_github_slug/releases/tags/$tag" | jq '.id // empty' )
		if [ -n "$release_id" ]; then
			echo "Updating GitHub release: https://github.com/$project_github_slug/releases/tag/$tag"
			_gh_release_url="-X PATCH https://api.github.com/repos/$project_github_slug/releases/$release_id"
		else
			echo "Creating GitHub release: https://github.com/$project_github_slug/releases/tag/$tag"
			_gh_release_url="https://api.github.com/repos/$project_github_slug/releases"
		fi
		result=$( echo "$_gh_payload" | curl -sS --retry 3 --retry-delay 10 \
				-w "%{http_code}" -o "$resultfile" \
				-H "Authorization: token $github_token" \
				-d @- \
				$_gh_release_url ) &&
		{
			if [ "$result" = "200" ] || [ "$result" = "201" ]; then # edited || created
				if [ -z "$release_id" ]; then
					release_id=$( jq '.id' < "$resultfile" )
				fi
				upload_github_asset "$release_id" "$archive_name" "$archive"
				if [ -f "$nolib_archive" ]; then
					upload_github_asset "$release_id" "$nolib_archive_name" "$nolib_archive"
				fi
			else
				echo "Error! ($result)"
				if [ -s "$resultfile" ]; then
					echo "$(<"$resultfile")"
				fi
				exit_code=1
			fi
		} || {
			exit_code=1
		}

		rm -f "$resultfile" 2>/dev/null
		echo
	fi
fi

# All done.

echo
echo "Packaging complete."
echo

exit $exit_code
