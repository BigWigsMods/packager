#!/bin/sh
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
#

# release.sh generates a zippable addon directory from a Git checkout.

# POSIX tools.
cat=cat
cp=cp
find=find
getopts=getopts
grep=grep
mkdir=mkdir
mv=mv
pwd=pwd
rm=rm
sed=sed
tr=tr

# Non-POSIX tools.
curl=curl
git=git
svn=svn
zip=zip

# pkzip wrapper for 7z.
sevenzip=7z
zip() {
	archive="$1"; shift
	$sevenzip a -tzip "$archive" "$@"
}

unix2dos() {
	$sed -i "s/$/\r/" "$1"
}

# Site URLs, used to find the localization web app.
site_url="http://wow.curseforge.com http://www.wowace.com"

# Variables set via options.
project=
topdir=
releasedir=
overwrite=
nolib=
skip_copying=
skip_externals=
skip_localization=
skip_zipfile=

# Set $topdir to top-level directory of the Git checkout.
if [ -z "$topdir" ]; then
	dir=$( $pwd )
	if [ -d "$dir/.git" ]; then
		topdir=.
	else
		dir=${dir%/*}
		topdir=..
		while [ -n "$dir" ]; do
			if [ -d "$topdir/.git" ]; then
				break
			fi
			dir=${dir%/*}
			topdir="$topdir/.."
		done
		if [ ! -d "$topdir/.git" ]; then
			echo "No Git checkout found." >&2
			exit 10
		fi
	fi
fi

# Set $releasedir to the directory which will contain the generated addon zipfile.
: ${releasedir:="$topdir/release"}

usage() {
	echo "Usage: release.sh [-celoz] [-n name] [-r releasedir] [-t topdir]" >&2
	echo "  -c               Skip copying files into the package directory." >&2
	echo "  -e               Skip checkout of external repositories." >&2
	echo "  -l               Skip @localization@ keyword replacement." >&2
	echo "  -n name          Set the name of the addon." >&2
	echo "  -o               Keep existing package directory; just overwrite contents." >&2
	echo "  -r releasedir    Set directory containing the package directory. Defaults to \`\`\$topdir/release''." >&2
	echo "  -s               Create a stripped-down \`\`nolib'' package." >&2
	echo "  -t topdir        Set top-level directory of Git checkout.  Defaults to \`\`$topdir''." >&2
	echo "  -z               Skip zipfile creation." >&2
}

# Process command-line options
OPTIND=1
while $getopts ":celn:or:st:z" opt; do
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
	n)
		project="$OPTARG"
		;;
	o)
		# Skip deleting any previous package directory.
		overwrite=true
		;;
	r)
		# Set the release directory to a non-default value.
		releasedir="$OPTARG"
		;;
	s)
		# Create a nolib package.
		nolib=true
		;;
	t)
		# Set the top-level directory of the Git checkout to a non-default value.
		topdir="$OPTARG"
		;;
	z)
		# Skip generating the zipfile.
		skip_zipfile=true
		;;
	:)
		echo "Option \`\`-$OPTARG'' requires an argument." >&2
		usage
		exit 1
		;;
	\?)
		echo "Unknown option \`\`-$OPTARG''." >&2
		usage
		exit 2
		;;
	esac
done
shift $((OPTIND - 1))

# Check that $topdir is actually a Git checkout.
if [ ! -d "$topdir/.git" ]; then
	echo "No Git checkout found in \`\`$topdir''." >&2
	exit 11
fi

# $releasedir must be an absolute path or relative to $topdir.
case $releasedir in
/*)			;;
$topdir/*)	;;
*)
	echo "The release directory \`\`$releasedir'' must be an absolute path or relative to \`\`$topdir''." >&2
	exit 20
	;;
esac

# Create the staging directory.
$mkdir -p "$releasedir"

# Expand $topdir and $releasedir to their absolute paths for string comparisons later.
topdir=$( cd "$topdir" && $pwd )
releasedir=$( cd "$releasedir" && $pwd )

# Get the tag for the HEAD.
tag=$( $git describe HEAD --abbrev=0 2>/dev/null )
# Find the previous release tag.
rtag=$( $git describe HEAD~1 --abbrev=0 2>/dev/null )
while true; do
	# A version string must contain only dots and digits and optionally starts with the letter "v".
	is_release_rtag=$( echo "${rtag#v}" | $sed -e "s/[0-9.]*//" )
	if [ -z "$is_release_rtag" ]; then
		break
	fi
	rtag=$( $git describe $rtag~1 --abbrev=0 2>/dev/null )
done
# If the current and previous tags match, then the HEAD is not tagged.
if [ "$tag" = "$rtag" ]; then
	tag=
else
	echo "Current tag: $tag"
fi
if [ -z "$rtag" ]; then
	echo "No previous release tag found."
else
	echo "Previous release tag: $rtag"
fi

# Set $version to the version number of HEAD.  May be empty if there are no commits.
version="$tag"
if [ -z "$version" ]; then
	version=$( $git describe HEAD 2>/dev/null )
	if [ -z "$version" ]; then
		version=$( $git rev-parse --short HEAD 2>/dev/null )
	fi
fi

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
	yaml_value=${yaml_value#"${yaml_value%%[! ]*}"}	# trim leading whitespace
}

yaml_listitem() {
	yaml_item=${1#-}
	yaml_item=${yaml_item#"${yaml_item%%[! ]*}"}	# trim leading whitespace
}

###
### Process .pkgmeta to set variables used later in the script.
###

# Variables set via .pkgmeta.
changelog=
changelog_markup="plain"
enable_nolib_creation="not supported"
ignore=
license=
contents=

if [ -f "$topdir/.pkgmeta" ]; then
	while IFS='' read -r yaml_line || [ -n "$yaml_line" ]; do
		case $yaml_line in
		[!\ ]*:*)
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key

			case $yaml_key in
			enable-nolib-creation)
				enable_nolib_creation=$yaml_value
				;;
			license-output)
				license=$yaml_value
				;;
			manual-changelog)
				changelog=$yaml_value
				;;
			package-as)
				package=$yaml_value
				;;
			esac
			;;
		" "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"}	# trim leading whitespace
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

# Set $package to the basename of the Git checkout directory if not already set.
if [ -z "$package" ]; then
	# Use the basename of the Git checkout directory as the package name.
	case $topdir in
	/*/*)
		package=${topdir##/*/}
		;;
	/*)
		package=${topdir##/}
		;;
	esac
fi

# Set $pkgdir to the path of the package directory inside $releasedir.
: ${pkgdir:="$releasedir/$package"}
if [ -d "$pkgdir" -a -z "$overwrite" ]; then
	echo "Removing previous package directory: $pkgdir"
	$rm -fr "$pkgdir"
fi
if [ ! -d "$pkgdir" ]; then
	$mkdir -p "$pkgdir"
fi

# Set the contents of the addon zipfile.
contents="$package"

###
### Create filters for pass-through processing of files to replace repository keywords.
###

# Filter for simple repository keyword replacement.
simple_filter()
{
	$sed \
		-e "s/@project-version@/$version/g"
}

# Find URL of localization app.
localization_url=
cache_localization_url() {
	if [ -z "$localization_url" ]; then
		for _ul_site_url in $site_url; do
			# Ensure that the CF/WA URL is lowercase, since project slugs are always in lowercase.
			localization_url=$( echo "${_ul_site_url}/addons/$package/localization" | $tr '[A-Z]' '[a-z]' )
			if $curl -s -I "$localization_url/" | $grep -q "200 OK"; then
				echo "Localization URL is: $localization_url"
				break
			fi
		done
	fi
}

# Filter to handle @localization@ repository keyword replacement.
localization_filter()
{
	while IFS='' read -r _ul_line || [ -n "$_ul_line" ]; do
		case $_ul_line in
		--@localization\(*\)@*)
			# Strip everything but the localization parameters.
			_ul_params=${_ul_line#*@localization(}
			_ul_params=${_ul_params%)@}
			# Generate a URL parameter string from the localization parameters.
			set -- ${_ul_params}
			_ul_url_params=
			_ul_skip_fetch=
			for _ul_param; do
				_ul_key=${_ul_param%%=*}
				_ul_value=${_ul_param#*=\"}
				_ul_value=${_ul_value%\"*}
				case ${_ul_key} in
					escape-non-ascii)
						if [ "$_ul_param" = "true" ]; then
							_ul_url_params="${_ul_url_params}&escape_non_ascii=y"
						fi
						;;
					format)
						_ul_url_params="${_ul_url_params}&format=${_ul_value}"
						;;
					handle-unlocalized)
						_ul_url_params="${_ul_url_params}&handle_unlocalized=${_ul_value}"
						;;
					handle-subnamespaces)
						_ul_url_params="${_ul_url_params}&handle_subnamespaces=${_ul_value}"
						;;
					locale)
						_ul_url_params="${_ul_url_params}&language=${_ul_value}"
						;;
					namespace)
						# Verify that the localization namespace is valid.  The CF packager will silently allow
						# and remove @localization@ calls with invalid namespaces.
						_ul_namespace_url=$( echo "${localization_url}/namespaces/${_ul_value}" | $tr '[A-Z]' '[a-z]' )
						if $curl -s -I "$_ul_namespace_url/" | $grep -q "200 OK"; then
							: "valid namespace"
						else
							echo "Invalid localization namespace \`\`$_ul_value''." >&2
							_ul_skip_fetch=true
						fi
						_ul_url_params="${_ul_url_params}&namespace=${_ul_value}"
						;;
				esac
			done
			# Strip any leading or trailing ampersands.
			_ul_url_params=${_ul_url_params#&}
			_ul_url_params=${_ul_url_params%&}
			if [ -z "$_ul_skip_fetch" ]; then
				$curl --progress-bar "${localization_url}/export.txt?${_ul_url_params}"
			fi
			# Insert a trailing blank line to match CF packager.
			echo ""
			;;
		*)
			echo "$_ul_line"
		esac
	done
}

lua_filter()
{
	$sed \
		-e "s/--@$1@/--[===[@$1/g" \
		-e "s/--@end-$1@/--@end-$1]===]/g" \
		-e "s/--\[===\[@non-$1@/--@non-$1@/g" \
		-e "s/--@end-non-$1@\]===\]/--@end-non-$1@/g"
}

toc_filter()
{
	_trf_token=$1; shift
	_trf_comment=
	while IFS='' read -r _trf_line || [ -n "$_trf_line" ]; do
		_trf_passthrough=
		case $_trf_line in
		"#@${_trf_token}@"*)
			_trf_comment="#"
			_trf_passthrough=true
			;;
		"#@end-${_trf_token}@"*)
			_trf_comment=
			_trf_passthrough=true
			;;
		esac
		if [ -n "$_trf_passthrough" ]; then
			echo "$_trf_line"
		else
			echo "$_trf_comment$_trf_line"
		fi
	done
}

xml_filter()
{
	$sed \
		-e "s/<!--@$1@-->/<!--@$1/g" \
		-e "s/<!--@end-$1@-->/@end-$1@-->/g" \
		-e "s/<!--@non-$1@/<!--@non-$1@-->/g" \
		-e "s/@end-non-$1@-->/<!--@end-non-$1@-->/g"
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
	_cdt_unchanged_patterns=
	OPTIND=1
	while $getopts :adi:lnu: _cdt_opt "$@"; do
		case $_cdt_opt in
		a)	_cdt_alpha=true ;;
		d)	_cdt_debug=true ;;
		i)	_cdt_ignored_patterns=$OPTARG ;;
		l)	_cdt_localization=true ;;
		n)	_cdt_nolib=true ;;
		u)	_cdt_unchanged_patterns=$OPTARG ;;
		esac
	done
	shift $((OPTIND - 1))
	_cdt_srcdir=$1
	_cdt_destdir=$2

	echo "Copying files from \`\`$_cdt_srcdir'' into \`\`$_cdt_destdir'':"
	if [ ! -d "$_cdt_destdir" ]; then
		$mkdir -p "$_cdt_destdir"
	fi
	# Create a "find" command to list all of the files in the source directory, minus any ones we need to prune.
	_cdt_find_cmd="$find \"$_cdt_srcdir\""
	# If the basename of the source directory begins with a dot, always descend into it, but prune everything else
	# that begins with a dot.
	case ${_cdt_srcdir##*/} in
	.*)	_cdt_find_cmd="$_cdt_find_cmd -name \"${_cdt_srcdir##*/}\" -print -o -name \".*\" -prune" ;;
	*)	_cdt_find_cmd="$_cdt_find_cmd -name \".*\" -prune" ;;
	esac
	# The destination directory needs to be pruned if it is a subdirectory of the source directory.
	_cdt_dest_subdir=${_cdt_destdir#${_cdt_srcdir}/}
	case $_cdt_dest_subdir in
	/*)	;;
	*)	_cdt_find_cmd="$_cdt_find_cmd -o -name \"$_cdt_dest_subdir\" -prune" ;;
	esac
	_cdt_find_cmd="$_cdt_find_cmd -o -print"
	eval $_cdt_find_cmd | while read file; do
		file=${file#$_cdt_srcdir/}
		if [ "$file" != "$_cdt_srcdir" -a -f "$_cdt_srcdir/$file" ]; then
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
				echo "Ignoring: $file"
			else
				dir=${file%/*}
				if [ "$dir" != "$file" ]; then
					$mkdir -p "$_cdt_destdir/$dir"
				fi
				# Check if the file matches a pattern for keyword replacement.
				skip_filter=true
				if match_pattern "$file" "*.lua:*.md:*.toc:*.txt:*.xml"; then
					skip_filter=
				fi
				if [ -n "$skip_filter" -o -n "$unchanged" ]; then
					echo "Copying: $file"
					$cp "$_cdt_srcdir/$file" "$_cdt_destdir/$dir"
				else
					# Set the filter for @localization@ replacement.
					_cdt_localization_filter=$cat
					if [ -n "$_cdt_localization" ]; then
						cache_localization_url
						_cdt_localization_filter=localization_filter
					fi
					# Set the alpha, debug, and nolib filters for replacement based on file extension.
					_cdt_alpha_filter=$cat
					if [ -n "$_cdt_alpha" ]; then
						case $file in
						*.lua)	_cdt_alpha_filter="lua_filter alpha" ;;
						*.toc)	_cdt_alpha_filter="toc_filter alpha" ;;
						*.xml)	_cdt_alpha_filter="xml_filter alpha" ;;
						esac
					fi
					_cdt_debug_filter=$cat
					if [ -n "$_cdt_debug" ]; then
						case $file in
						*.lua)	_cdt_debug_filter="lua_filter debug" ;;
						*.toc)	_cdt_debug_filter="toc_filter debug" ;;
						*.xml)	_cdt_debug_filter="xml_filter debug" ;;
						esac
					fi
					_cdt_nolib_filter=$cat
					if [ -n "$_cdt_nolib" ]; then
						case $file in
						*.toc)	_cdt_nolib_filter="toc_filter no-lib-strip" ;;
						*.xml)	_cdt_nolib_filter="xml_filter no-lib-strip" ;;
						esac
					fi
					# As a side-effect, files that don't end in a newline silently have one added.
					# POSIX does imply that text files must end in a newline.
					echo "Copying: $file"
					$cat "$_cdt_srcdir/$file" | simple_filter | $_cdt_alpha_filter | $_cdt_debug_filter | $_cdt_nolib_filter | $_cdt_localization_filter > "$_cdt_destdir/$file"
					unix2dos "$_cdt_destdir/$file"
				fi
			fi
		fi
	done
}

if [ -z "$skip_copying" ]; then
	cdt_args=
	if [ -z "$tag" ]; then
		# HEAD is not tagged, so this is an alpha.
		cdt_args="$cdt_args -a"
	fi
	if true; then
		# Debug is always "false" in a packaged addon.
		cdt_args="$cdt_args -d"
	fi
	if [ -z "$skip_localization" ]; then
		cdt_args="$cdt_args -l"
	fi
	if [ -n "$nolib" ]; then
		cdt_args="$cdt_args -n"
	fi
	if [ -n "$ignore" ]; then
		cdt_args="$cdt_args -i \"$ignore\""
	fi
	if [ -n "$changelog" ]; then
		cdt_args="$cdt_args -u \"$changelog\""
	fi
	eval copy_directory_tree $cdt_args "\"$topdir\"" "\"$pkgdir\""
fi

# Create a default license if one doesn't exist.
create_license=
if [ -z "$license" ]; then
	license="LICENSE.txt"
fi
# Create a default license in the package directory if the source directory does
# not contain a license file.
if [ ! -f "$topdir/$license" ]; then
	create_license=true
fi
if [ -n "$create_license" ]; then
	echo "Generating default license into $license."
	echo "All Rights Reserved." > "$pkgdir/$license"
	unix2dos "$pkgdir/$license"
fi

###
### Process .pkgmeta again to perform any pre-move-folders actions.
###

# Queue for external checkouts.
external_dir=
external_uri=
external_tag=

# Sites that are skipped for checking out externals if creating a "nolib" package.
external_nolib_sites="curseforge.com wowace.com"

checkout_queued_external() {
	_cqe_skip_external=$skip_externals
	if [ -z "$external_dir" -o -z "$external_uri" ]; then
		# The queue is empty.
		_cqe_skip_external=true
	elif [ -n "$nolib" ]; then
		for _cqe_nolib_site in $external_nolib_sites; do
			case $external_uri in
			*${_cqe_nolib_site}/*)
				# The URI points to a Curse repository, so we can skip this external
				# for a "nolib" package.
				echo "Ignoring external to Curse repository: $external_uri"
				_cqe_skip_external=true
				break
				;;
			esac
		done
	fi
	if [ -z "$_cqe_skip_external" ]; then
		# Checkout the external into a ".checkout" subdirectory of the final directory.
		_cqe_checkout_dir="$pkgdir/$external_dir/.checkout"
		$mkdir -p "$_cqe_checkout_dir"
		case $external_uri in
		git:*|http://git*|https://git*)
			if [ -z "$external_tag" ]; then
				echo "Fetching latest version of external $external_uri."
				$git clone --depth 1 "$external_uri" "$_cqe_checkout_dir"
			elif [ "$external_tag" != "latest" ]; then
				echo "Fetching tag \`\`$external_tag'' of external $external_uri."
				$git clone --depth 1 --branch "$external_tag" "$external_uri" "$_cqe_checkout_dir"
			else
				# We need to determine the latest tag in a remote Git repository:
				#
				#	1. Clone the latest 100 commits from the remote repository.
				#	2. Find the most recent annotated tag.
				#	3. Checkout that tag into the working directory.
				#	4. If no tag is found, then leave the latest commit as the checkout.
				#
				echo "Fetching external $external_uri."
				$git clone --depth 100 "$external_uri" "$_cqe_checkout_dir"
				external_tag=$(
					cd "$_cqe_checkout_dir"
					latest_tag=$( $git for-each-ref refs/tags --sort=-taggerdate --format="%(refname)" --count=1 )
					latest_tag=${latest_tag#refs/tags/}
					if [ -n "$latest_tag" ]; then
						echo "$latest_tag"
					else
						echo "latest"
					fi
				)
				if [ "$external_tag" != "latest" ]; then
					echo "Checking out \`\`$external_tag'' into \`\`$_cqe_checkout_dir''."
					( cd "$_cqe_checkout_dir" && $git checkout "$external_tag" )
				fi
			fi
			;;
		svn:*|http://svn*|https://svn*)
			if [ -n "$external_tag" -a "$external_tag" != "latest" ]; then
				echo "Warning: SVN tag checkout for \`\`$external_tag'' must be given in the URI."
			fi
			echo "Fetching external $external_uri."
			$svn checkout "$external_uri" "$_cqe_checkout_dir"
			;;
		*)
			echo "Unknown external: $external_uri" >&2
			;;
		esac
		# Copy the checkout into the proper external directory and remove the checkout.
		(
			cd "$_cqe_checkout_dir"
			# Set variables needed for filters.
			if [ -z "$external_tag" ]; then
				version=$( $git describe HEAD 2>/dev/null )
				if [ -z "$version" ]; then
					version=$( $git rev-parse --short HEAD 2>/dev/null )
				fi
			else
				version="$external_tag"
			fi
			package=${external_dir##*/}
			for _cqe_nolib_site in $external_nolib_sites; do
				case $external_uri in
				*${_cqe_nolib_site}/*)
					# The URI points to a Curse repository.
					package=${external_uri#*${_cqe_nolib_site}/wow/}
					package=${package%%/*}
					break
					;;
				esac
			done
			localization_url=
			# If a .pkgmeta file is present, process it for an "ignore" list.
			ignore=
			if [ -f "$_cqe_checkout_dir/.pkgmeta" ]; then
				while IFS='' read -r yaml_line; do
					case $yaml_line in
					[!\ ]*:*)
						# Split $yaml_line into a $yaml_key, $yaml_value pair.
						yaml_keyvalue "$yaml_line"
						# Set the $pkgmeta_phase for stateful processing.
						pkgmeta_phase=$yaml_key
						;;
					" "*)
						yaml_line=${yaml_line#"${yaml_line%%[! ]*}"}	# trim leading whitespace
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
			copy_directory_tree -dln -i "$ignore" "$_cqe_checkout_dir" "$pkgdir/$external_dir"
		)
		# Remove the ".checkout" subdirectory containing the full checkout.
		if [ -d "$_cqe_checkout_dir" ]; then
			rm -fr "$_cqe_checkout_dir"
		fi
	fi
	# Clear the queue.
	external_dir=
	external_uri=
	external_tag=
}

if [ -f "$topdir/.pkgmeta" ]; then
	while IFS='' read -r yaml_line; do
		case $yaml_line in
		[!\ ]*:*)
			# Started a new section, so checkout any queued externals.
			checkout_queued_external
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key
			;;
		" "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"}	# trim leading whitespace
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
						checkout_queued_external
						external_dir=$yaml_key
						if [ -n "$yaml_value" ]; then
							external_uri=$yaml_value
							# Immediately checkout this fully-specified external.
							checkout_queued_external
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
	checkout_queued_external
fi

###
### Create the changelog of commits since the previous release tag.
###

# Find the name of the project if unset.
if [ -z "$project" ]; then
	# Parse the TOC file if it exists for the title of the project.
	if [ -f "$topdir/$package.toc" ]; then
		while read toc_line; do
			case $toc_line in
			"## Title: "*)
				project=${toc_line#"## Title: "}
				;;
			esac
		done < "$topdir/$package.toc"
	fi
fi
# Default to the name of the package directory.
: ${project:="$package"}

# Create changelog of commits since the previous release tag.
create_changelog=
if [ -z "$changelog" ]; then
	changelog="CHANGELOG.txt"
fi
# Create a changelog in the package directory if the source directory does
# not contain a manual changelog.
if [ ! -f "$topdir/$changelog" ]; then
	create_changelog=true
fi
if [ -n "$create_changelog" ]; then
	if [ -n "$rtag" ]; then
		echo "Generating changelog of commits since $rtag into $changelog."
		change_string="Changes from version $rtag:"
		git_commit_range="$rtag..HEAD"
	else
		echo "Generating changelog of commits into $changelog."
		change_string="All changes:"
		git_commit_range=
	fi
	change_string_underline=$( echo "$change_string" | $sed -e "s/./-/g" )
	project_string="$project $version"
	project_string_underline=$( echo "$project_string" | $sed -e "s/./=/g" )
	$cat > "$pkgdir/$changelog" << EOF
$project_string
$project_string_underline

$change_string
$change_string_underline

EOF
	$git log $git_commit_range --pretty=format:"###   %B" |
		$sed -e "s/^/    /g" -e "s/^ *$//g" -e "s/^    ###/-/g" >> "$pkgdir/$changelog"
	unix2dos "$pkgdir/$changelog"
fi

###
### Process .pkgmeta to perform move-folders actions.
###

if [ -f "$topdir/.pkgmeta" ]; then
	while IFS='' read -r yaml_line; do
		case $yaml_line in
		[!\ ]*:*)
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key
			;;
		" "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"}	# trim leading whitespace
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
						echo "Removing previous moved folder: $destdir"
						$rm -fr "$destdir"
					fi
					if [ -d "$srcdir" ]; then
						if [ -z "$overwrite" ]; then
							echo "Moving \`\`$yaml_key'' to \`\`$destdir''"
							$mv "$srcdir" "$destdir"
						else
							echo "Copying contents of \`\`$yaml_key'' to \`\`$destdir''"
							$mkdir -p "$destdir"
							$find "$srcdir" -print | while read file; do
								file=${file#"$releasedir/"}
								if [ "$file" != "$releasedir" -a -f "$releasedir/$file" ]; then
									dir=${file%/*}
									if [ "$dir" != "$file" ]; then
										$mkdir -p "$destdir/$dir"
									fi
									$cp "$releasedir/$file" "$destdir/$dir"
									echo "Copied: $file"
								fi
							done
						fi
						contents="$contents $yaml_value"
						# Copy the license into $destdir if one doesn't already exist.
						if [ ! -f "$destdir/$license" ]; then
							$cp -f "$pkgdir/$license" "$destdir/$license"
						fi
					fi
					;;
				esac
				;;
			esac
			;;
		esac
	done < "$topdir/.pkgmeta"
fi

###
### Create the final zipfile for the addon.
###

if [ -z "$skip_zipfile" ]; then
	archive="$releasedir/$package-$version.zip"
	if [ -f "$archive" ]; then
		echo "Removing previous archive: $archive"
		$rm -f "$archive"
	fi
	( cd "$releasedir" && $zip "$archive" $contents )
fi
