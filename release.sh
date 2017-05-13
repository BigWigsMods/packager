#!/bin/bash

# release.sh generates a zippable addon directory from a Git or SVN checkout.
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

# add some travis checks so we don't need to do it in the yaml file
if [ -n "$TRAVIS" ]; then
	# don't need to run the packager for pull requests
	if [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
		echo "Not packaging pull request."
		exit 0
	fi
	# only want to package master and tags
	if [ "$TRAVIS_BRANCH" != "master" -a -z "$TRAVIS_TAG" ]; then
		echo "Not packaging \"${TRAVIS_BRANCH}\"."
		exit 0
	fi
	# don't need to run the packager if there is a tag pending (or already built)
	if [ -z "$TRAVIS_TAG" ]; then
		TRAVIS_COMMIT_TIMESTAMP=$( git -C "$TRAVIS_BUILD_DIR" show --no-patch --format='%at' $TRAVIS_COMMIT)
		for tag in $(git -C "$TRAVIS_BUILD_DIR" for-each-ref --sort=-taggerdate --count=3 --format '%(refname:short)' refs/tags); do
			if [[ $( git -C "$TRAVIS_BUILD_DIR" cat-file -p "$tag" | awk '/^tagger/ {print $(NF-1); exit}' ) > $TRAVIS_COMMIT_TIMESTAMP ]]; then
				echo "Found future tag '$tag', not packaging."
				exit 0
			fi
		done
	fi
fi

# Script return code
exit_code=0

# Game versions for uploading
game_version=
game_version_id=

# Secrets for uploading
cf_token=$CF_API_KEY
github_token=$GITHUB_OAUTH
wowi_token=$WOWI_API_TOKEN

# Variables set via options.
slug=
addonid=
topdir=
releasedir=
overwrite=
nolib=
line_ending=dos
skip_copying=
skip_externals=
skip_localization=
skip_zipfile=
skip_upload=

# Process command-line options
usage() {
	echo "Usage: release.sh [-cdelosuz] [-t topdir] [-r releasedir] [-p curse-id] [-w wowi-id] [-g game-version]" >&2
	echo "  -c               Skip copying files into the package directory." >&2
	echo "  -d               Skip uploading." >&2
	echo "  -e               Skip checkout of external repositories." >&2
	echo "  -l               Skip @localization@ keyword replacement." >&2
	echo "  -o               Keep existing package directory, overwriting its contents." >&2
	echo "  -s               Create a stripped-down \"nolib\" package." >&2
	echo "  -u               Use Unix line-endings." >&2
	echo "  -z               Skip zipfile creation." >&2
	echo "  -t topdir        Set top-level directory of checkout." >&2
	echo "  -r releasedir    Set directory containing the package directory. Defaults to \"\$topdir/.release\"." >&2
	echo "  -p curse-id      Set the project id used on CurseForge for localization and uploading." >&2
	echo "  -w wowi-id       Set the addon id used on WoWInterface for uploading." >&2
	echo "  -g game-version  Set the game version to use for CurseForge and WoWInterface uploading." >&2
}

OPTIND=1
while getopts ":celzusop:dw:r:t:g:" opt; do
	case $opt in
	c)
		# Skip copying files into the package directory.
		skip_copying=true
		;;
	e)
		# Skip checkout of external repositories.
		skip_externals=true
		;;
	l)
		# Skip @localization@ keyword replacement.
		skip_localization=true
		;;
	d)
		# Skip uploading.
		skip_upload=true
		;;
	o)
		# Skip deleting any previous package directory.
		overwrite=true
		;;
	p)
		slug="$OPTARG"
		;;
	w)
		addonid="$OPTARG"
		;;
	r)
		# Set the release directory to a non-default value.
		releasedir="$OPTARG"
		;;
	s)
		# Create a nolib package.
		nolib=true
		skip_externals=true
		;;
	t)
		# Set the top-level directory of the checkout to a non-default value.
		topdir="$OPTARG"
		;;
	u)
		# Skip Unix-to-DOS line-ending translation.
		line_ending=unix
		;;
	z)
		# Skip generating the zipfile.
		skip_zipfile=true
		;;
	g)
		# Set version (x.y.z)
		if [[ "$OPTARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+[a-z]?$ ]]; then
			game_version="$OPTARG"
		else
			echo "Invalid argument for option \"-g\" ($OPTARG)" >&2
			usage
			exit 1
		fi
		;;
	:)
		echo "Option \"-$OPTARG\" requires an argument." >&2
		usage
		exit 1
		;;
	\?)
		if [ "$OPTARG" != "?" -a "$OPTARG" != "h" ]; then
			echo "Unknown option \"-$OPTARG\"." >&2
		fi
		usage
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

# Set $topdir to top-level directory of the checkout.
if [ -z "$topdir" ]; then
	dir=$( pwd )
	if [ -d "$dir/.git" -o -d "$dir/.svn" ]; then
		topdir=.
	else
		dir=${dir%/*}
		topdir=..
		while [ -n "$dir" ]; do
			if [ -d "$topdir/.git" -o -d "$topdir/.svn" ]; then
				break
			fi
			dir=${dir%/*}
			topdir="$topdir/.."
		done
		if [ ! -d "$topdir/.git" -a ! -d "$topdir/.svn" ]; then
			echo "No Git or SVN checkout found." >&2
			exit 1
		fi
	fi
fi

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

# Set $repository_type to "git" or "svn".
repository_type=
if [ -d "$topdir/.git" ]; then
	repository_type=git
elif [ -d "$topdir/.svn" ]; then
	repository_type=svn
else
	echo "No Git or SVN checkout found in \"$topdir\"." >&2
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
mkdir -p "$releasedir"

# Expand $topdir and $releasedir to their absolute paths for string comparisons later.
topdir=$( cd "$topdir" && pwd )
releasedir=$( cd "$releasedir" && pwd )

package=$basedir
tocfile=$( cd "$topdir" && ls *.toc -1 2>/dev/null | head -n 1 )
if [ -f "$topdir/$tocfile" ]; then
	# Set the package name from the TOC filename.
	package=${tocfile%.toc}
	# Parse the TOC file for the title of the project used in the changelog.
	project=$( grep '## Title:' "$topdir/$tocfile" | sed -e 's/## Title\s*:\s*\(.*\)\s*/\1/' -e 's/|c[0-9A-Fa-f]\{8\}//g' -e 's/|r//g' )
	# Grab CurseForge slug and WoWI ID from the TOC file.
	if [ -z "$slug" ]; then
		slug=$( awk '/## X-Curse-Project-ID:/ { print $NF }' < "$topdir/$tocfile" )
	fi
	if [ -z "$addonid" ]; then
		addonid=$( awk '/## X-WoWI-ID:/ { print $NF }' < "$topdir/$tocfile" )
	fi
fi

###
### set_info_<repo> returns the following information:
###
si_repo_type= # "git" or "svn"
si_repo_dir= # the checkout directory
si_repo_url= # the checkout url
si_tag= # tag for HEAD
si_previous_tag= # previous tag
si_previous_revision= # [SVN] revision number for previous tag

si_project_revision= # Turns into the highest revision of the entire project in integer form, e.g. 1234, for SVN. Turns into the commit count for the project's hash for Git.
si_project_hash= # [Git] Turns into the hash of the entire project in hex form. e.g. 106c634df4b3dd4691bf24e148a23e9af35165ea
si_project_abbreviated_hash= # [Git] Turns into the abbreviated hash of the entire project in hex form. e.g. 106c63f
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

set_info_git() {
	si_repo_dir="$1"
	si_repo_type="git"
	si_repo_url=$( git -C "$si_repo_dir" remote get-url origin 2>/dev/null | sed -e 's/^git@\(.*\):/https:\/\/\1\//' )
	if [ -z "$si_repo_url" ]; then # no origin so grab the first fetch url
		si_repo_url=$( git -C "$si_repo_dir" remote -v | grep '(fetch)' | awk '{ print $2; exit }' | sed -e 's/^git@\(.*\):/https:\/\/\1\//' )
	fi

	# Populate filter vars.
	si_project_hash=$( git -C "$si_repo_dir" show --no-patch --format="%H" 2>/dev/null )
	si_project_abbreviated_hash=$( git -C "$si_repo_dir" show --no-patch --format="%h" 2>/dev/null )
	si_project_author=$( git -C "$si_repo_dir" show --no-patch --format="%an" 2>/dev/null )
	si_project_timestamp=$( git -C "$si_repo_dir" show --no-patch --format="%at" 2>/dev/null )
	si_project_date_iso=$( date -ud "@$si_project_timestamp" -Iseconds 2>/dev/null )
	si_project_date_integer=$( date -ud "@$si_project_timestamp" +%Y%m%d%H%M%S 2>/dev/null )
	# XXX --depth limits rev-list :\ [ ! -s "$(git rev-parse --git-dir)/shallow" ] || git fetch --unshallow --no-tags
	si_project_revision=$( git -C "$si_repo_dir" rev-list --count $si_project_hash 2>/dev/null )

	# Get the tag for the HEAD.
	si_previous_tag=
	si_previous_revision=
	_si_tag=$( git -C "$si_repo_dir" describe --tags --always 2>/dev/null )
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
		si_project_version=$_si_tag
		si_previous_tag=$si_tag
		si_tag=
	else # we're on a tag, just jump back one commit
		si_previous_tag=$( git -C "$si_repo_dir" describe --tags --abbrev=0 HEAD~ 2>/dev/null )
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
				si_project_revision=$( svn info --recursive "$si_repo_dir" 2>/dev/null | awk '/^Last Changed Rev:/ { print $NF }' | sort -nr | head -1 )
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
		_si_timestamp=$( awk '/^Last Changed Date:/ { print $4,$5,$6; exit }' < "$_si_svninfo" )
		si_project_timestamp=$( date -ud "$_si_timestamp" +%s 2>/dev/null )
		si_project_date_iso=$( date -ud "$_si_timestamp" -Iseconds 2>/dev/null )
		si_project_date_integer=$( date -ud "$_si_timestamp" +%Y%m%d%H%M%S 2>/dev/null )
		# SVN repositories have no project hash.
		si_project_hash=
		si_project_abbreviated_hash=

		rm -f "$_si_svninfo" 2>/dev/null
	fi
}

set_info_file() {
	if [ "$si_repo_type" = "git" ]; then
		_si_file=${1#si_repo_dir} # need the path relative to the checkout
		# Populate filter vars from the last commit the file was included in.
		si_file_hash=$( git -C "$si_repo_dir" log --max-count=1 --format="%H" "$_si_file" 2>/dev/null )
		si_file_abbreviated_hash=$( git -C "$si_repo_dir" log --max-count=1  --format="%h"  "$_si_file" 2>/dev/null )
		si_file_author=$( git -C "$si_repo_dir" log --max-count=1 --format="%an" "$_si_file" 2>/dev/null )
		si_file_timestamp=$( git -C "$si_repo_dir" log --max-count=1 --format="%at" "$_si_file" 2>/dev/null )
		si_file_date_iso=$( date -ud "@$si_file_timestamp" -Iseconds 2>/dev/null )
		si_file_date_integer=$( date -ud "@$si_file_timestamp" +%Y%m%d%H%M%S 2>/dev/null )
		si_file_revision=$( git -C "$si_repo_dir" rev-list --count $si_file_hash 2>/dev/null )
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
			si_file_timestamp=$( date -ud "$_si_timestamp" +%s 2>/dev/null )
			si_file_date_iso=$( date -ud "$_si_timestamp" -Iseconds 2>/dev/null )
			si_file_date_integer=$( date -ud "$_si_timestamp" +%Y%m%d%H%M%S 2>/dev/null )
			# SVN repositories have no project hash.
			si_file_hash=
			si_file_abbreviated_hash=

			rm -f "$_sif_svninfo" 2>/dev/null
		fi
	fi
}

# Set some version info about the project
case $repository_type in
git)	set_info_git "$topdir" ;;
svn)	set_info_svn "$topdir" ;;
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

# Set the slug for cf/wowace checkouts.
if [ -z "$slug" ] && [[ "$si_repo_url" == *"curseforge.com"* || "$si_repo_url" == *"wowace.com"* ]]; then
	slug=${si_repo_url#*/wow/}
	slug=${slug%%/*}
fi
# The default slug is the lowercase basename of the checkout directory.
if [ -z "$slug" ]; then
	slug=$( echo "$basedir" | tr '[:upper:].' '[:lower:]-' )
fi

# Bare carriage-return character.
carriage_return=$( printf "\r" )

# Returns 0 if $1 matches one of the colon-separated patterns in $2.
match_pattern() {
	_mp_file=$1
	_mp_list="$2:"
	while [ -n "$_mp_list" ]; do
		_mp_pattern=${_mp_list%%:*}
		_mp_list=${_mp_list#*:}
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

# Variables set via .pkgmeta.
manual_changelog=
changelog=
changelog_markup="plain"
enable_nolib_creation=
ignore=
license=
contents=
nolib_exclude=
wowi_gen_changelog=true
wowi_archive=true

if [ -f "$topdir/.pkgmeta" ]; then
	yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof=true
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
					enable_nolib_creation=true
				fi
				;;
			license-output)
				license=$yaml_value
				;;
			manual-changelog)
				changelog=$yaml_value
				manual_changelog=true
				;;
			package-as)
				package=$yaml_value
				;;
			wowi-create-changelog)
				if [ "$yaml_value" = "no" ]; then
					wowi_gen_changelog=
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
					fi
					if [ -z "$ignore" ]; then
						ignore="$pattern"
					else
						ignore="$ignore:$pattern"
					fi
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
						manual_changelog=true
						;;
					markup-type)
						changelog_markup=$yaml_value
						;;
					esac
					;;
				esac
				;;
			esac
			;;
		esac
	done < "$topdir/.pkgmeta"
fi

# Add untracked/ignored files to the ignore list
if [ "$repository_type" = "git" ]; then
	_vcs_ignore=$( git -C "$topdir" ls-files --others | sed -e ':a' -e 'N' -e 's/\n/:/' -e 'ta' )
	if [ -n "$_vcs_ignore" ]; then
		if [ -z "$ignore" ]; then
			ignore="$_vcs_ignore"
		else
			ignore="$ignore:$_vcs_ignore"
		fi
	fi
elif [ "$repository_type" = "svn" ]; then
	# svn always being difficult.
	OLDIFS=$IFS
	IFS=$'\n'
	for _vcs_ignore in $( cd "$topdir" && svn status --no-ignore | grep '^[?I]' | cut -c9- | tr '\\' '/' ); do
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
fi

echo
if [ -z "$nolib" ]; then
	echo "Packaging $package"
else
	echo "Packaging $package (nolib)"
fi
if [ -n "$project_version" ]; then
	echo "Current version: $project_version"
fi
if [ -n "$previous_version" ]; then
	echo "Previous version: $previous_version"
fi
if [ -n "$slug" ]; then
	echo "CurseForge ID: $slug${cf_token:+ [token set]}"
fi
if [ -n "$addonid" ]; then
	echo "WoWInterface ID: $addonid${wowi_token:+ [token set]}"
fi
if [ -n "$project_github_slug" ]; then
	echo "GitHub: $project_github_slug${github_token:+ [token set]}"
fi
echo
echo "Checkout directory: $topdir"
echo "Release directory: $releasedir"
echo

# Set $pkgdir to the path of the package directory inside $releasedir.
pkgdir="$releasedir/$package"
if [ -d "$pkgdir" -a -z "$overwrite" ]; then
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

# Filter for simple repository keyword replacement.
simple_filter() {
	sed \
		-e "s/@project-revision@/$si_project_revision/g" \
		-e "s/@project-hash@/$si_project_hash/g" \
		-e "s/@project-abbreviated-hash@/$si_project_abbreviated_hash/g" \
		-e "s/@project-author@/$si_project_author/g" \
		-e "s/@project-date-iso@/$si_project_date_iso/g" \
		-e "s/@project-date-integer@/$si_project_date_integer/g" \
		-e "s/@project-timestamp@/$si_project_timestamp/g" \
		-e "s/@project-version@/$si_project_version/g" \
		-e "s/@file-revision@/$si_file_revision/g" \
		-e "s/@file-hash@/$si_file_hash/g" \
		-e "s/@file-abbreviated-hash@/$si_file_abbreviated_hash/g" \
		-e "s/@file-author@/$si_file_author/g" \
		-e "s/@file-date-iso@/$si_file_date_iso/g" \
		-e "s/@file-date-integer@/$si_file_date_integer/g" \
		-e "s/@file-timestamp@/$si_file_timestamp/g"
}

# Find URL of localization api.
set_localization_url() {
	localization_url=
	if [ -n "$slug" -a -n "$cf_token" ] && [[ "$slug" =~ ^[0-9]+$ ]]; then
		# There is no good way of differentiating between sites short of using different TOC fields for CF and WowAce
		# Curse does redirect to the proper site when using the project id, so we'll use that to get the API url
		_ul_test_url="https://wow.curseforge.com/projects/$slug"
		_ul_test_url_result=$( curl -s -L -w "%{url_effective}" -o /dev/null $_ul_test_url )
		if [ "$_ul_test_url" != "$_ul_test_url_result" ]; then
			localization_url="${_ul_test_url_result%%/project*}/api/projects/$slug/localization/export"
		fi
	fi
	if [ -z "$localization_url" ]; then
		echo "Skipping localization! Missing CurseForge API token and/or project id is invalid."
		echo
	fi
}

# Filter to handle @localization@ repository keyword replacement.
# https://www.curseforge.com/knowledge-base/world-of-warcraft/531-localization-substitutions
declare -A unlocalized_values=( ["english"]="ShowPrimary" ["comment"]="ShowPrimaryAsComment" ["blank"]="ShowBlankAsComment" ["ignore"]="Ignore" )
localization_filter() {
	_ul_eof=
	while [ -z "$_ul_eof" ]; do
		IFS='' read -r _ul_line || _ul_eof=true
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
			# Generate a URL parameter string from the localization parameters. https://www.curseforge.com/docs/api
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
						if [ "$_ul_value" != "english" -a -n "${unlocalized_values[$_ul_value]}" ]; then
							_ul_url_params="${_ul_url_params}&unlocalized=${unlocalized_values[$_ul_value]}"
						fi
						;;
					handle-subnamespaces)
						if [ "$_ul_value" = "concat" ]; then # concat with /
							_ul_url_params="${_ul_url_params}&concatenante-subnamespaces=true"
						elif [ "$_ul_value" = "subtable" ]; then
							echo "    ($_ul_lang) Warning! ${_ul_key}=\"${_ul_value}\" is not supported. Use format=\"lua_table\" instead." >&2
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
						_ul_namespace="/${_ul_value}"
						# _ul_url_params="${_ul_url_params}&namespaces=${_ul_value##*/}" # strip parent namespace(s)
						_ul_url_params="${_ul_url_params}&namespaces=${_ul_value}"
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

			if [ -z "$_cdt_localization" -o -z "$localization_url" ]; then
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
					if [ -n "$_ul_value" -a "$_ul_value" != "$_ul_singlekey" ]; then
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
	sed \
		-e "s/--@$1@/--[===[@$1@/g" \
		-e "s/--@end-$1@/--@end-$1@]===]/g" \
		-e "s/--\[===\[@non-$1@/--@non-$1@/g" \
		-e "s/--@end-non-$1@\]===\]/--@end-non-$1@/g"
}

toc_filter() {
	_trf_token=$1; shift
	_trf_comment=
	_trf_eof=
	while [ -z "$_trf_eof" ]; do
		IFS='' read -r _trf_line || _trf_eof=true
		# Strip any trailing CR character.
		_trf_line=${_trf_line%$carriage_return}
		_trf_passthrough=
		case $_trf_line in
		"#@${_trf_token}@"*)
			_trf_comment="# "
			_trf_passthrough=true
			;;
		"#@end-${_trf_token}@"*)
			_trf_comment=
			_trf_passthrough=true
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
	if [ -z "$_dnpf_start_token" -o -z "$_dnpf_end_token" ]; then
		cat
	else
		# Replace all content between the start and end tokens, inclusive, with a newline to match CF packager.
		_dnpf_eof=
		_dnpf_skip=
		while [ -z "$_dnpf_eof" ]; do
			IFS='' read -r _dnpf_line || _dnpf_eof=true
			# Strip any trailing CR character.
			_dnpf_line=${_dnpf_line%$carriage_return}
			case $_dnpf_line in
			*$_dnpf_start_token*)
				_dnpf_skip=true
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
		IFS='' read -r _lef_line || _lef_eof=true
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
	OPTIND=1
	while getopts :adi:lnpu: _cdt_opt "$@"; do
		case $_cdt_opt in
		a)	_cdt_alpha=true ;;
		d)	_cdt_debug=true ;;
		i)	_cdt_ignored_patterns=$OPTARG ;;
		l)	_cdt_localization=true
			set_localization_url
			;;
		n)	_cdt_nolib=true ;;
		p)	_cdt_do_not_package=true ;;
		u)	_cdt_unchanged_patterns=$OPTARG ;;
		esac
	done
	shift $((OPTIND - 1))
	_cdt_srcdir=$1
	_cdt_destdir=$2

	echo "Copying files into ${_cdt_destdir#$topdir/}:"
	if [ ! -d "$_cdt_destdir" ]; then
		mkdir -p "$_cdt_destdir"
	fi
	# Create a "find" command to list all of the files in the current directory, minus any ones we need to prune.
	_cdt_find_cmd="find ."
	# Prune everything that begins with a dot except for the current directory ".".
	_cdt_find_cmd="$_cdt_find_cmd \( -name \".*\" -a \! -name \".\" \) -prune"
	# Prune the destination directory if it is a subdirectory of the source directory.
	_cdt_dest_subdir=${_cdt_destdir#${_cdt_srcdir}/}
	case $_cdt_dest_subdir in
	/*)	;;
	*)	_cdt_find_cmd="$_cdt_find_cmd -o -path \"./$_cdt_dest_subdir\" -prune" ;;
	esac
	# Print the filename, but suppress the current directory ".".
	_cdt_find_cmd="$_cdt_find_cmd -o \! -name \".\" -print"
	( cd "$_cdt_srcdir" && eval $_cdt_find_cmd ) | while read file; do
		file=${file#./}
		if [ -f "$_cdt_srcdir/$file" ]; then
			# Check if the file should be ignored.
			skip_copy=
			# Skip files matching the colon-separated "ignored" shell wildcard patterns.
			if [ -z "$skip_copy" ] && match_pattern "$file" "$_cdt_ignored_patterns"; then
				skip_copy=true
			fi
			# Never skip files that match the colon-separated "unchanged" shell wildcard patterns.
			unchanged=
			if [ -n "$skip_copy" ] && match_pattern "$file" "$_cdt_unchanged_patterns"; then
				skip_copy=
				unchanged=true
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
				skip_filter=true
				if match_pattern "$file" "*.lua:*.md:*.toc:*.txt:*.xml"; then
					skip_filter=
				fi
				if [ -n "$skip_filter" -o -n "$unchanged" ]; then
					echo "  Copying: $file (unchanged)"
					cp "$_cdt_srcdir/$file" "$_cdt_destdir/$dir"
				else
					# Set the filter for @localization@ replacement.
					_cdt_localization_filter=cat
					if [ -n "$_cdt_localization" ]; then
						_cdt_localization_filter=localization_filter
					fi
					# Set the alpha, debug, and nolib filters for replacement based on file extension.
					_cdt_alpha_filter=cat
					if [ -n "$_cdt_alpha" ]; then
						case $file in
						*.lua)	_cdt_alpha_filter="lua_filter alpha" ;;
						*.toc)	_cdt_alpha_filter="toc_filter alpha" ;;
						*.xml)	_cdt_alpha_filter="xml_filter alpha" ;;
						esac
					fi
					_cdt_debug_filter=cat
					if [ -n "$_cdt_debug" ]; then
						case $file in
						*.lua)	_cdt_debug_filter="lua_filter debug" ;;
						*.toc)	_cdt_debug_filter="toc_filter debug" ;;
						*.xml)	_cdt_debug_filter="xml_filter debug" ;;
						esac
					fi
					_cdt_nolib_filter=cat
					if [ -n "$_cdt_nolib" ]; then
						case $file in
						*.toc)	_cdt_nolib_filter="toc_filter no-lib-strip" ;;
						*.xml)	_cdt_nolib_filter="xml_filter no-lib-strip" ;;
						esac
					fi
					_cdt_do_not_package_filter=cat
					if [ -n "$_cdt_do_not_package" ]; then
						case $file in
						*.lua)	_cdt_do_not_package_filter="do_not_package_filter lua" ;;
						*.toc)	_cdt_do_not_package_filter="do_not_package_filter toc" ;;
						*.xml)	_cdt_do_not_package_filter="do_not_package_filter xml" ;;
						esac
					fi
					# As a side-effect, files that don't end in a newline silently have one added.
					# POSIX does imply that text files must end in a newline.
					set_info_file "$_cdt_srcdir/$file"
					echo "  Copying: $file"
					cat "$_cdt_srcdir/$file" \
						| simple_filter \
						| $_cdt_alpha_filter \
						| $_cdt_debug_filter \
						| $_cdt_nolib_filter \
						| $_cdt_do_not_package_filter \
						| $_cdt_localization_filter \
						| line_ending_filter \
						> "$_cdt_destdir/$file"
				fi
			fi
		fi
	done
}

if [ -z "$skip_copying" ]; then
	cdt_args="-dp"
	if [ -n "$tag" ]; then
		cdt_args="${cdt_args}a"
	fi
	if [ -z "$skip_localization" ]; then
		cdt_args="${cdt_args}l"
	fi
	if [ -n "$nolib" ]; then
		cdt_args="${cdt_args}n"
	fi
	if [ -n "$ignore" ]; then
		cdt_args="$cdt_args -i \"$ignore\""
	fi
	if [ -n "$changelog" ]; then
		cdt_args="$cdt_args -u \"$changelog\""
	fi
	eval copy_directory_tree $cdt_args "\"$topdir\"" "\"$pkgdir\""
	echo
fi

###
### Create a default license if not present and .pkgmeta requests one.
###

if [ -n "$license" -a ! -f "$topdir/$license" ]; then
	echo "Generating license into $license."
	echo "All Rights Reserved." | line_ending_filter > "$pkgdir/$license"
	echo
fi

###
### Process .pkgmeta again to perform any pre-move-folders actions.
###

# Checkout the external into a ".checkout" subdirectory of the final directory.
checkout_external() {
	_external_dir=$1
	_external_uri=$2
	_external_tag=$3
	_external_type=$4
	_cqe_checkout_dir="$pkgdir/$_external_dir/.checkout"
	mkdir -p "$_cqe_checkout_dir"
	echo
	if [ "$_external_type" = "git" ]; then
		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			git clone -q --depth 1 "$_external_uri" "$_cqe_checkout_dir"
			if [ $? -ne 0 ]; then return 1; fi
		elif [ "$_external_tag" != "latest" ]; then
			echo "Fetching tag \"$_external_tag\" from external $_external_uri"
			git clone -q --depth 1 --branch "$_external_tag" "$_external_uri" "$_cqe_checkout_dir"
			if [ $? -ne 0 ]; then return 1; fi
		else # [ "$_external_tag" = "latest" ]; then
			git clone -q --depth 50 "$_external_uri" "$_cqe_checkout_dir"
			if [ $? -ne 0 ]; then return 1; fi
			_external_tag=$( git -C "$_cqe_checkout_dir" for-each-ref refs/tags --sort=-taggerdate --format=%\(refname:short\) --count=1 )
			if [ -n "$_external_tag" ]; then
				echo "Fetching tag \"$_external_tag\" from external $_external_uri"
				git -C "$_cqe_checkout_dir" checkout -q "$_external_tag"
			else
				echo "Fetching latest version of external $_external_uri"
			fi
		fi
		set_info_git "$_cqe_checkout_dir"
		echo "Checked out $( git -C "$_cqe_checkout_dir" describe --always --tags --long )" #$si_project_abbreviated_hash
	elif [ "$_external_type" = "svn" ]; then
		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			svn checkout -q "$_external_uri" "$_cqe_checkout_dir"
			if [ $? -ne 0 ]; then return 1; fi
		else
			case $_external_uri in
			*/trunk)
				_cqe_svn_trunk_url=$_external_uri
				_cqe_svn_subdir=
				;;
			*)
				_cqe_svn_trunk_url="${_external_uri%/trunk/*}/trunk"
				_cqe_svn_subdir=${_external_uri#${_cqe_svn_trunk_url}/}
				;;
			esac
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
				svn checkout -q "$_external_uri" "$_cqe_checkout_dir"
				if [ $? -ne 0 ]; then return 1; fi
			else
				_cqe_external_uri="${_cqe_svn_tag_url}/$_external_tag"
				if [ -n "$_cqe_svn_subdir" ]; then
					_cqe_external_uri="${_cqe_external_uri}/$_cqe_svn_subdir"
				fi
				echo "Fetching tag \"$_external_tag\" from external $_cqe_external_uri"
				svn checkout -q "$_cqe_external_uri" "$_cqe_checkout_dir"
				if [ $? -ne 0 ]; then return 1; fi
			fi
		fi
		set_info_svn "$_cqe_checkout_dir"
		echo "Checked out r$si_project_revision"
	else
		echo "Unknown external: $_external_uri" >&2
		return 1
	fi
	# Copy the checkout into the proper external directory.
	(
		cd "$_cqe_checkout_dir" || return 1
		# Set the slug for external localization, if needed.
		slug=
		if [[ "$_external_uri" == *"curseforge.com"* || "$_external_uri" == *"wowace.com"* ]]; then
			slug=${_external_uri#*/wow/}
			slug=${slug%%/*}
		fi
		# If a .pkgmeta file is present, process it for an "ignore" list.
		ignore=
		if [ -f "$_cqe_checkout_dir/.pkgmeta" ]; then
			yaml_eof=
			while [ -z "$yaml_eof" ]; do
				IFS='' read -r yaml_line || yaml_eof=true
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
						# Get the YAML list item.
						yaml_listitem "$yaml_line"
						case $pkgmeta_phase in
						ignore)
							pattern=$yaml_item
							if [ -d "$topdir/$pattern" ]; then
								pattern="$pattern/*"
							fi
							if [ -z "$ignore" ]; then
								ignore="$pattern"
							else
								ignore="$ignore:$pattern"
							fi
							;;
						esac
						;;
					esac
					;;
				esac
			done < "$_cqe_checkout_dir/.pkgmeta"
		fi
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
process_external() {
	if [ -n "$external_dir" -a -n "$external_uri" -a -z "$skip_externals" ]; then
		echo "Fetching external: $external_dir"
		(
			# convert old curse repo urls and detect the type of new ones
			# this could be condensed quite a bit.. a task for another day
			case $external_uri in
			git:*|http://git*|https://git*)
				external_type=git
				if [[ "$external_uri" == "git://git.curseforge.com"* || "$external_uri" == "git://git.wowace.com"* ]]; then
					# git://git.(curseforge|wowace).com/wow/$slug/mainline.git -> https://repos.curseforge.com/wow/$slug
					external_uri=${external_uri%/mainline.git}
					external_uri=${external_uri/#git:\/\/git/https://repos}
				fi
				;;
			svn:*|http://svn*|https://svn*)
				external_type=svn
				if [[ "$external_uri" == "svn://svn.curseforge.com"* || "$external_uri" == "svn://svn.wowace.com"* ]]; then
					# svn://svn.(curseforge|wowace).com/wow/$slug/mainline/trunk -> https://repos.curseforge.com/wow/$slug/trunk
					external_uri=${external_uri/\/mainline/}
					external_uri=${external_uri/#svn:\/\/svn/https://repos}
				fi
				;;
			https://repos.curseforge.com/wow/*|https://repos.wowace.com/wow/*)
				_pe_path=${external_uri#*/wow/}
				_pe_path=${_pe_path#*/} # remove the slug, leaving nothing for git or the svn path
				# note: the svn repo trunk is used as the url with another field specifying a tag instead of using the tags dir directly
				# not sure if by design or convention, but hopefully remains true
				if [[ "$_pe_path" == "trunk"* ]]; then
					external_type=svn
				else
					external_type=git
				fi
				;;
			esac

			output_file="$releasedir/.${RANDOM}.externalout"
			checkout_external "$external_dir" "$external_uri" "$external_tag" "$external_type" &> "$output_file"
			status=$?
			cat "$output_file" 2>/dev/null
			rm -f "$output_file" 2>/dev/null
			exit $status
		) &
		external_pids+=($!)
	fi
	external_dir=
	external_uri=
	external_tag=
	external_type=
}

# Don't leave extra files around if exited early
kill_externals() {
	rm -f "$releasedir"/.*.externalout
	kill 0
}
trap kill_externals INT

if [ -z "$skip_externals" -a -f "$topdir/.pkgmeta" ]; then
	yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof=true
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
					url)
						# Queue external URI for checkout.
						external_uri=$yaml_value
						;;
					tag)
						# Queue external tag for checkout.
						external_tag=$yaml_value
						;;
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
	done < "$topdir/.pkgmeta"
	# Reached end of file, so checkout any remaining queued externals.
	process_external

	if [ -n "$nolib_exclude" ]; then
		echo
		echo "Waiting for externals to finish..."
		for i in ${!external_pids[*]}; do
			if ! wait ${external_pids[i]}; then
				_external_error=1
			fi
		done
		if [ -n "$_external_error" ]; then
			echo
			echo "There was an error fetching externals :("
			exit 1
		fi
		echo
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
if [ -z "$changelog" ]; then
	changelog="CHANGELOG.md"
	changelog_markup="markdown"
fi
if [[ -n "$manual_changelog" && -f "$topdir/$changelog" && "$changelog_markup" == "markdown" ]]; then
	# Convert Markdown to BBCode (with HTML as an intermediary) for sending to WoWInterface
	# Requires pandoc (http://pandoc.org/)
	_html_changelog=
	if which pandoc &>/dev/null; then
		_html_changelog=$( pandoc -t html "$topdir/$changelog" )
	fi
	if [ -n "$_html_changelog" ]; then
		wowi_changelog="$releasedir/WOWI-$project_version-CHANGELOG.txt"
		echo "$_html_changelog" | sed \
			-e 's/<\(\/\)\?\(b\|i\|u\)>/[\1\2]/g' \
			-e 's/<\(\/\)\?em>/[\1i]/g' \
			-e 's/<\(\/\)\?strong>/[\1b]/g' \
			-e 's/<ul[^>]*>/[list]/g' -e 's/<ol[^>]*>/[list="1"]/g' \
			-e 's/<\/[ou]l>/[\/list]\n/g' \
			-e 's/<li>/[*]/g' -e 's/<\/li>//g' -e '/^\s*$/d' \
			-e 's/<h1[^>]*>/[size="6"]/g' -e 's/<h2[^>]*>/[size="5"]/g' -e 's/<h3[^>]*>/[size="4"]/g' \
			-e 's/<h4[^>]*>/[size="3"]/g' -e 's/<h5[^>]*>/[size="3"]/g' -e 's/<h6[^>]*>/[size="3"]/g' \
			-e 's/<\/h[1-6]>/[\/size]\n/g' \
			-e 's/<a href=\"\([^"]\+\)\"[^>]*>/[url="\1"]/g' -e 's/<\/a>/\[\/url]/g' \
			-e 's/<img src=\"\([^"]\+\)\"[^>]*>/[img]\1[\/img]/g' \
			-e 's/<\(\/\)\?blockquote>/[\1quote]\n/g' \
			-e 's/<pre><code>/[code]\n/g' -e 's/<\/code><\/pre>/[\/code]\n/g' \
			-e 's/<code>/[font="monospace"]/g' -e 's/<\/code>/[\/font]/g' \
			-e 's/<\/p>/\n/g' \
			-e 's/<[^>]\+>//g' \
			-e 's/&quot;/"/g' \
			-e 's/&amp;/&/g' \
			-e 's/&lt;/</g' \
			-e 's/&gt;/>/g' \
			-e "s/&#39;/'/g" \
			| line_ending_filter > "$wowi_changelog"

			# extra conversion for discount markdown
			# -e 's/&\(ld\|rd\)quo;/"/g' \
			# -e "s/&\(ls\|rs\)quo;/'/g" \
			# -e 's/&ndash;/--/g' \
			# -e 's/&hellip;/.../g' \
			# -e 's/^[ \t]*//g' \
	fi
fi
if [ ! -f "$topdir/$changelog" -a ! -f "$topdir/CHANGELOG.txt" -a ! -f "$topdir/CHANGELOG.md" ]; then
	if [ -n "$manual_changelog" ]; then
		echo "Warning! Could not find a manual changelog at $topdir/$changelog"
		manual_changelog=
		changelog="CHANGELOG.md"
		changelog_markup="markdown"
	fi
	echo "Generating changelog of commits into $changelog"

	if [ "$repository_type" = "git" ]; then
		changelog_url=
		changelog_version=
		changelog_url_wowi=
		changelog_version_wowi=
		git_commit_range=
		if [ -z "$previous_version" -a -z "$tag" ]; then
			# no range, show all commits up to ours
			changelog_url="[Full Changelog](${project_github_url}/commits/$project_hash)"
			changelog_version="[$project_version](${project_github_url}/tree/$project_hash)"
			changelog_url_wowi="[url=${project_github_url}/commits/$project_hash]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/$project_hash]$project_version[/url]"
			git_commit_range="$project_hash"
		elif [ -z "$previous_version" -a -n "$tag" ]; then
			# first tag, show all commits upto it
			changelog_url="[Full Changelog](${project_github_url}/commits/$tag)"
			changelog_version="[$project_version](${project_github_url}/tree/$tag)"
			changelog_url_wowi="[url=${project_github_url}/commits/$tag]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/$tag]$project_version[/url]"
			git_commit_range="$tag"
		elif [ -n "$previous_version" -a -z "$tag" ]; then
			# compare between last tag and our commit
			changelog_url="[Full Changelog](${project_github_url}/compare/$previous_version...$project_hash)"
			changelog_version="[$project_version](${project_github_url}/tree/$project_hash)"
			changelog_url_wowi="[url=${project_github_url}/compare/$previous_version...$project_hash]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/$project_hash]$project_version[/url]"
			git_commit_range="$previous_version..$project_hash"
		elif [ -n "$previous_version" -a -n "$tag" ]; then
			# compare between last tag and our tag
			changelog_url="[Full Changelog](${project_github_url}/compare/$previous_version...$tag)"
			changelog_version="[$project_version](${project_github_url}/tree/$tag)"
			changelog_url_wowi="[url=${project_github_url}/compare/$previous_version...$tag]Full Changelog[/url]"
			changelog_version_wowi="[url=${project_github_url}/tree/$tag]$project_version[/url]"
			git_commit_range="$previous_version..$tag"
		fi
		# lazy way out
		if [ -z "$project_github_url" ]; then
			changelog_url=
			changelog_version=$project_version
			changelog_url_wowi=
			changelog_version_wowi="[color=orange]$project_version[/color]"
		fi
		changelog_date=$( date -ud "@$project_timestamp" +%Y-%m-%d )

		cat <<- EOF | line_ending_filter > "$pkgdir/$changelog"
		# $project

		## $changelog_version ($changelog_date)
		$changelog_url

		EOF
		git -C "$topdir" log $git_commit_range --pretty=format:"###%B" \
			| sed -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/- /g' \
			      -e 's/$/  /' \
			      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
			      -e '/git-svn-id:/d' -e '/^\s*This reverts commit [0-9a-f]\{40\}\.\s*$/d' \
			      -e '/^\s*$/d' \
			| line_ending_filter >> "$pkgdir/$changelog"

		# WoWI uses BBCode, generate something usable to post to the site
		# the file is deleted on successful upload
		if [ -n "$addonid" -a -n "$tag" -a -n "$wowi_gen_changelog" ]; then
			changelog_previous_wowi=
			if [ -n "$project_github_url" -a -n "$github_token" ]; then
				changelog_previous_wowi="[url=${project_github_url}/releases]Previous releases[/url]"
			fi
			wowi_changelog="$releasedir/WOWI-$project_version-CHANGELOG.txt"
			cat <<- EOF | line_ending_filter > "$wowi_changelog"
			[size=5]$project[/size]
			[size=4]$changelog_version_wowi ($changelog_date)[/size]
			$changelog_url_wowi $changelog_previous_wowi
			[list]
			EOF
			git -C "$topdir" log $git_commit_range --pretty=format:"###%B" \
				| sed -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/[*]/g' \
				      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
				      -e '/git-svn-id:/d' -e '/^\s*This reverts commit [0-9a-f]\{40\}\.\s*$/d' \
				      -e '/^\s*$/d' \
				| line_ending_filter >> "$wowi_changelog"
			echo "[/list]" | line_ending_filter >> "$wowi_changelog"

		fi

	elif [ "$repository_type" = "svn" ]; then
		svn_revision_range=
		if [ -n "$previous_version" ]; then
			svn_revision_range="-r$project_revision:$previous_revision"
		fi
		changelog_date=$( date -ud "@$project_timestamp" +%Y-%m-%d )

		cat <<- EOF | line_ending_filter > "$pkgdir/$changelog"
		# $project

		## $project_version ($changelog_date)

		EOF
		svn log "$topdir" $svn_revision_range --xml \
			| awk '/<msg>/,/<\/msg>/' \
			| sed -e 's/<msg>/###/g' -e 's/<\/msg>//g' -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/- /g' \
			      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
			      -e '/^\s*$/d' \
			| line_ending_filter >> "$pkgdir/$changelog"

		# WoWI uses BBCode, generate something usable to post to the site
		# the file is deleted on successful upload
		if [ -n "$addonid" -a -n "$tag" -a -n "$wowi_gen_changelog" ]; then
			wowi_changelog="$releasedir/WOWI-$project_version-CHANGELOG.txt"
			cat <<- EOF | line_ending_filter > "$wowi_changelog"
			[size=5]$project[/size]
			[size=4][color=orange]$project_version[/color] ($changelog_date)[/size]

			[list]
			EOF
			svn log "$topdir" $svn_revision_range --xml \
				| awk '/<msg>/,/<\/msg>/' \
				| sed -e 's/<msg>/###/g' -e 's/<\/msg>//g' -e 's/^/    /g' -e 's/^ *$//g' -e 's/^    ###/[*]/g' \
				      -e 's/\[ci skip\]//g' -e 's/\[skip ci\]//g' \
				      -e '/^\s*$/d' \
				| line_ending_filter >> "$wowi_changelog"
			echo "[/list]" | line_ending_filter >> "$wowi_changelog"

		fi
	fi

	echo
	cat "$pkgdir/$changelog"
	echo
fi

###
### Process .pkgmeta to perform move-folders actions.
###

if [ -f "$topdir/.pkgmeta" ]; then
	yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof=true
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
					if [ -d "$destdir" -a -z "$overwrite" ]; then
						rm -fr "$destdir"
					fi
					if [ -d "$srcdir" ]; then
						if [ ! -d "$destdir" ]; then
							mkdir -p "$destdir"
						fi
						echo "Moving $yaml_key to $yaml_value"
						mv -f "$srcdir"/* "$destdir" && rm -fr "$srcdir"
						contents="$contents $yaml_value"
						# Copy the license into $destdir if one doesn't already exist.
						if [ -n "$license" -a -f "$pkgdir/$license" -a ! -f "$destdir/$license" ]; then
							cp -f "$pkgdir/$license" "$destdir/$license"
						fi
						# Check to see if the base source directory is empty
						_mf_basedir=${srcdir%$(basename "$yaml_key")}
						if [ ! "$(ls -A $_mf_basedir )" ]; then
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
	done < "$topdir/.pkgmeta"
	if [ -n "$srcdir" ]; then
		echo
	fi
fi

###
### Create the final zipfile for the addon.
###

if [ -z "$skip_zipfile" ]; then
	archive_package_name="${package//[^A-Za-z0-9._-]/_}"

	archive_version="$project_version"
	archive_name="$archive_package_name-$project_version.zip"
	archive="$releasedir/$archive_name"

	nolib_archive_version="$project_version-nolib"
	nolib_archive_name="$archive_package_name-$nolib_archive_version.zip"
	nolib_archive="$releasedir/$nolib_archive_name"

	if [ -n "$nolib" ]; then
		archive_version="$nolib_archive_version"
		archive_name="$nolib_archive_name"
		archive="$nolib_archive"
		nolib_archive=
	fi

	echo "Creating archive: $archive_name"

	if [ -f "$archive" ]; then
		rm -f "$archive"
	fi
	( cd "$releasedir" && zip -X -r "$archive" $contents )

	if [ ! -f "$archive" ]; then
		exit 1
	fi
	echo

	# Create nolib version of the zipfile
	if [ -n "$enable_nolib_creation" -a -z "$nolib" -a -n "$nolib_exclude" ]; then
		echo "Creating no-lib archive: $nolib_archive_name"

		# run the nolib_filter
		find "$pkgdir" -type f \( -name "*.xml" -o -name "*.toc" \) -print | while read file; do
			case $file in
			*.toc)	_filter="toc_filter no-lib-strip" ;;
			*.xml)	_filter="xml_filter no-lib-strip" ;;
			esac
			$_filter < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
		done

		# make the exclude paths relative to the release directory
		nolib_exclude=${nolib_exclude//$releasedir\//}

		if [ -f "$nolib_archive" ]; then
			rm -f "$nolib_archive"
		fi
		# set noglob so each nolib_exclude path gets quoted instead of expanded
		( set -f; cd "$releasedir" && zip -X -r -q "$nolib_archive" $contents -x $nolib_exclude )

		if [ ! -f "$nolib_archive" ]; then
			exit_code=1
		fi
		echo
	fi

	###
	### Deploy the zipfile.
	###

	upload_curseforge=$( test -z "$skip_upload" -a -n "$slug" -a -n "$cf_token" && echo true )
	upload_wowinterface=$( test -z "$skip_upload" -a -n "$tag" -a -n "$addonid" -a -n "$wowi_token" && echo true )
	upload_github=$( test -z "$skip_upload" -a -n "$tag" -a -n "$project_github_slug" -a -n "$github_token" && echo true )

	if [ -n "$upload_curseforge" -o -n "$upload_wowinterface" -o -n "$upload_github" ] && ! which jq &>/dev/null; then
		echo "Skipping upload because \"jq\" was not found."
		echo
		upload_curseforge=
		upload_wowinterface=
		upload_github=
		exit_code=1
	fi

	if [ -n "$upload_curseforge" ]; then
		if [ -n "$game_version" ]; then
			game_version_id=$( curl -s -H "x-api-token: $cf_token" https://wow.curseforge.com/api/game/versions | jq -r '.[] | select(.name == "'$game_version'") | .id' 2>/dev/null )
		fi
		if [ -z "$game_version_id" ]; then
			game_version_id=$( curl -s -H "x-api-token: $cf_token" https://wow.curseforge.com/api/game/versions | jq -r 'max_by(.id) | .id' 2>/dev/null )
			game_version=$( curl -s -H "x-api-token: $cf_token" https://wow.curseforge.com/api/game/versions | jq -r 'max_by(.id) | .name' 2>/dev/null )
		fi
		if [ -z "$game_version_id" ]; then
			echo "Error fetching game version info from https://wow.curseforge.com/api/game/versions"
			echo
			echo "Skipping upload to CurseForge."
			echo
			upload_curseforge=
			exit_code=1
		fi
	fi

	if [ -n "$upload_wowinterface" ]; then
		if [ -n "$game_version" ]; then
			game_version=$( curl -s -H "x-api-token: $wowi_token" https://api.wowinterface.com/addons/compatible.json | jq -r '.[] | select(.id == "'$game_version'") | .id' 2>/dev/null )
		fi
		if [ -z "$game_version" ]; then
			game_version=$( curl -s -H "x-api-token: $wowi_token" https://api.wowinterface.com/addons/compatible.json | jq -r '.[] | select(.default == true) | .id' 2>/dev/null )
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

	# Upload to CurseForge.
	if [ -n "$upload_curseforge" ]; then
		# If the tag contains only dots and digits and optionally starts with
		# the letter v (such as "v1.2.3" or "v1.23" or "3.2") or contains the
		# word "release", then it is considered a release tag. If the above
		# conditions don't match, it is considered a beta tag. Untagged commits
		# are considered alphas.
		file_type=alpha
		if [ -n "$tag" ]; then
			if [[ "$tag" =~ ^v?[0-9][0-9.]*$ || "$tag" == *"release"* ]]; then
				file_type=release
			else
				file_type=beta
			fi
		fi

		_cf_payload=$( cat <<-EOF
		{
		  "displayName": "$project_version",
		  "gameVersions": [$game_version_id],
		  "releaseType": "$file_type",
		  "changelog": $( cat "$pkgdir/$changelog" | jq --slurp --raw-input '.' ),
		  "changelogType": "markdown"
		}
		EOF
		)

		echo "Uploading $archive_name ($game_version $file_type) to https://wow.curseforge.com/addons/$slug"
		resultfile="$releasedir/cf_result.json"
		result=$( curl -sS --retry 3 --retry-delay 10 \
				-w "%{http_code}" -o "$resultfile" \
				-H "x-api-token: $cf_token" \
				-F "metadata=$_cf_payload" \
				-F "file=@$archive" \
				"https://wow.curseforge.com/api/projects/$slug/upload-file" )
		if [ $? -eq 0 ]; then
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
		else
			exit_code=1
		fi
		echo

		rm -f "$resultfile" 2>/dev/null
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
			  "https://api.wowinterface.com/addons/update" )
		if [ $? -eq 0 ]; then
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
		else
			exit_code=1
		fi
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
			echo -n "Uploading $_ghf_file_name... "
			result=$( curl -sS --retry 3 --retry-delay 10 \
					-w "%{http_code}" -o "$_ghf_resultfile" \
					-H "Authorization: token $github_token" \
					-H "Content-Type: application/zip" \
					--data-binary "@$_ghf_file_path" \
					"https://uploads.github.com/repos/$project_github_slug/releases/$_ghf_release_id/assets?name=$_ghf_file_name" )
			if [ $? -eq 0 ]; then
				if [ "$result" -eq "201" ]; then
					echo "Success!"
				else
					echo "Error ($result)"
					if [ -s "$_ghf_resultfile" ]; then
						echo "$(<"$_ghf_resultfile")"
					fi
					exit_code=1
				fi
			else
				exit_code=1
			fi

			rm -f "$_ghf_resultfile" 2>/dev/null
		}

		# check if a release exists and delete it
		release_id=$( curl -sS "https://api.github.com/repos/$project_github_slug/releases/tags/$tag" | jq '.id | select(. != null)' )
		if [ -n "$release_id" ]; then
			curl -s -H "Authorization: token $github_token" -X DELETE "https://api.github.com/repos/$project_github_slug/releases/$release_id" &>/dev/null
			release_id=
		fi

		_gh_payload=$( cat <<-EOF
		{
		  "tag_name": "$tag",
		  "target_commitish": "master",
		  "name": "$tag",
		  "body": $( cat "$pkgdir/$changelog" | jq --slurp --raw-input '.' ),
		  "draft": false,
		  "prerelease": false
		}
		EOF
		)

		echo "Creating GitHub release: https://github.com/$project_github_slug/releases/tag/$tag"
		resultfile="$releasedir/gh_result.json"
		result=$( curl -sS --retry 3 --retry-delay 10 \
				-w "%{http_code}" -o "$resultfile" \
				-H "Authorization: token $github_token" \
				-d "$_gh_payload" \
				"https://api.github.com/repos/$project_github_slug/releases" )
		if [ $? -eq 0 ]; then
			if [ "$result" = "201" ]; then
				release_id=$( cat "$resultfile" | jq '.id' )
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
		else
			exit_code=1
		fi
		echo

		rm -f "$resultfile" 2>/dev/null
	fi
fi

# All done.

echo "Packaging complete."
echo

exit $exit_code
