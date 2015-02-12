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
cmp=cmp
cp=cp
find=find
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
	dir=`pwd`
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
while getopts ":celn:or:st:z" opt; do
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
topdir=`cd "$topdir" && pwd`
releasedir=`cd "$releasedir" && pwd`

# Get the tag for the HEAD.
tag=`$git describe HEAD --abbrev=0 2>/dev/null`
# Find the previous release tag.
rtag=`$git describe HEAD~1 --abbrev=0 2>/dev/null`
while true; do
	# A version string must contain only dots and digits and optionally starts with the letter "v".
	is_release_rtag=`echo "${rtag#v}" | $sed -e "s/[0-9.]*//"`
	if [ -z "$is_release_rtag" ]; then
		break
	fi
	rtag=`$git describe $rtag~1 --abbrev=0 2>/dev/null`
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
	version=`$git describe HEAD 2>/dev/null`
	if [ -z "$version" ]; then
		version=`$git rev-parse --short HEAD 2>/dev/null`
	fi
fi

# Variables set via .pkgmeta.
changelog=
changelog_markup="plain"
enable_nolib_creation="not supported"
ignore=
license=
contents=

### Simple .pkgmeta YAML processor.

yaml_keyvalue() {
	yaml_key=${1%%:*}
	yaml_value=${1#$yaml_key:}
	yaml_value=${yaml_value#"${yaml_value%%[! ]*}"}	# trim leading whitespace
}

yaml_listitem() {
	yaml_item=${1#-}
	yaml_item=${yaml_item#"${yaml_item%%[! ]*}"}	# trim leading whitespace
}

# First scan of .pkgmeta to set variables.
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

# Filter for simple repository keyword replacement.
simple_filter()
{
	$sed \
		-e "s/@project-version@/$version/g"
}

# Find URL of localization app.
localization_url=
if [ -z "$skip_localization" -a -z "$localization_url" ]; then
	for _ul_site_url in $site_url; do
		# Ensure that the CF/WA URL is lowercase, since project slugs are always in lowercase.
		localization_url=`echo "${_ul_site_url}/addons/$package/localization" | $tr '[A-Z]' '[a-z]'`
		if $curl -s -I "$localization_url/" | $grep -q "200 OK"; then
			echo ">>> HERE" >&2
			break
		fi
	done
fi

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
						_ul_namespace_url=`echo "${localization_url}/namespaces/${_ul_value}" | $tr '[A-Z]' '[a-z]'`
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

lua_alpha_filter()
{
	$sed \
		-e "s/--@alpha@/--[===[@alpha/g" \
		-e "s/--@end-alpha@/--@end-alpha]===]/g" \
		-e "s/--\[===\[@non-alpha@/--@non-alpha@/g" \
		-e "s/--@end-non-alpha@\]===\]/--@end-non-alpha@/g"
}

lua_debug_filter()
{
	$sed \
		-e "s/--@debug@/--[===[@debug/g" \
		-e "s/--@end-debug@/--@end-debug]===]/g" \
		-e "s/--\[===\[@non-debug@/--@non-debug@/g" \
		-e "s/--@end-non-debug@\]===\]/--@end-non-debug@/g"
}

toc_alpha_filter()
{
	_trf_alpha=
	while IFS='' read -r _trf_line || [ -n "$_trf_line" ]; do
		_trf_replace=true
		case $_trf_line in
		"#@alpha@")
			_trf_alpha="#"
			_trf_replace=
			;;
		"#@end-alpha@")
			_trf_alpha=
			_trf_replace=
			;;
		esac
		if [ -z "$_trf_replace" ]; then
			echo "$_trf_line"
		else
			echo "$_trf_alpha$_trf_line"
		fi
	done
}

toc_debug_filter()
{
	_trf_debug=
	while IFS='' read -r _trf_line || [ -n "$_trf_line" ]; do
		_trf_replace=true
		case $_trf_line in
		"#@debug@")
			_trf_debug="#"
			_trf_replace=
			;;
		"#@end-debug@")
			_trf_debug=
			_trf_replace=
			;;
		esac
		if [ -z "$_trf_replace" ]; then
			echo "$_trf_line"
		else
			echo "$_trf_debug$_trf_line"
		fi
	done
}

toc_nolib_filter()
{
	_trf_nolib=
	while IFS='' read -r _trf_line || [ -n "$_trf_line" ]; do
		_trf_replace=true
		case $_trf_line in
		"#@no-lib-strip@")
			_trf_nolib="#"
			_trf_replace=
			;;
		"#@end-no-lib-strip@")
			_trf_nolib=
			_trf_replace=
			;;
		esac
		if [ -z "$_trf_replace" ]; then
			echo "$_trf_line"
		else
			echo "$_trf_nolib$_trf_line"
		fi
	done
}

xml_alpha_filter()
{
	$sed \
		-e "s/<!--@alpha@-->/<!--@alpha/g" \
		-e "s/<!--@end-alpha@-->/@end-alpha@-->/g" \
		-e "s/<!--@non-alpha@/<!--@non-alpha@-->/g" \
		-e "s/@end-non-alpha@-->/<!--@end-non-alpha@-->/g"
}

xml_debug_filter()
{
	$sed \
		-e "s/<!--@debug@-->/<!--@debug/g" \
		-e "s/<!--@end-debug@-->/@end-debug@-->/g" \
		-e "s/<!--@non-debug@/<!--@non-debug@-->/g" \
		-e "s/@end-non-debug@-->/<!--@end-non-debug@-->/g"
}

xml_nolib_filter()
{
	$sed \
		-e "s/<!--@no-lib-strip@-->/<!--@no-lib-strip/g" \
		-e "s/<!--@end-no-lib-strip@-->/@end-no-lib-strip@-->/g"
}

# Copy files from working directory into the package directory.
# Prune away any files in the .git and release directories.
if [ -z "$skip_copying" ]; then
	echo "Copying files into \`\`$pkgdir'':"
	$find "$topdir" -name .git -prune -o -name "${releasedir#$topdir/}" -prune -o -print | while read file; do
		file=${file#$topdir/}
		if [ "$file" != "$topdir" -a -f "$topdir/$file" ]; then
			unchanged=
			# Check if the file should be ignored.
			ignored=
			# Ignore files that start with a dot.
			if [ -z "$ignored" ]; then
				case $file in
				.*)
					echo "Ignoring: $file"
					ignored=true
					;;
				esac
			fi
			# Ignore files matching patterns set via .pkgmeta "ignore".
			if [ -z "$ignored" ]; then
				list="$ignore:"
				while [ -n "$list" ]; do
					pattern=${list%%:*}
					list=${list#*:}
					case $file in
					$pattern)
						echo "Ignoring: $file"
						ignored=true
						break
						;;
					esac
				done
			fi
			# Special-case manual changelogs which should never be ignored.
			if [ -n "$changelog" ]; then
				case $file in
				$changelog)
					ignored=
					unchanged=true
					;;
				esac
			fi
			# Copy any unignored files into $pkgdir.
			if [ -z "$ignored" ]; then
				dir=${file%/*}
				if [ "$dir" != "$file" ]; then
					$mkdir -p "$pkgdir/$dir"
				fi
				# Check if the file matches a pattern for keyword replacement.
				keyword="*.lua:*.md:*.toc:*.txt:*.xml"
				list="$keyword:"
				replaced=
				while [ -n "$list" ]; do
					pattern=${list%%:*}
					list=${list#*:}
					case $file in
					$pattern)
						replaced=true
						break
						;;
					esac
				done
				if [ -n "$replaced" -a -z "$unchanged" ]; then
					# Set the filter for @localization@ replacement.
					localization_filter=localization_filter
					if [ -n "$skip_localization" ]; then
						localization_filter=cat
					fi
					# Set the alpha, debug, and nolib filters for replacement based on file extension.
					alpha_filter=cat
					debug_filter=cat
					nolib_filter=cat
					if [ -z "$tag" ]; then
						# HEAD is not tagged, so this is an alpha.
						case $file in
						*.lua)	alpha_filter=lua_alpha_filter ;;
						*.toc)	alpha_filter=toc_alpha_filter ;;
						*.xml)	alpha_filter=xml_alpha_filter ;;
						esac
					fi
					if true; then
						# Debug is always "false" in a packaged addon.
						case $file in
						*.lua)	debug_filter=lua_debug_filter ;;
						*.toc)	debug_filter=toc_debug_filter ;;
						*.xml)	debug_filter=xml_debug_filter ;;
						esac
					fi
					if [ -n "$nolib" ]; then
						# Create a "nolib" package.
						case $file in
						*.toc)	nolib_filter=toc_nolib_filter ;;
						*.xml)	nolib_filter=xml_nolib_filter ;;
						esac
					fi
					# As a side-effect, files that don't end in a newline silently have one added.
					# POSIX does imply that text files must end in a newline.
					$cat "$topdir/$file" | simple_filter | $alpha_filter | $debug_filter | $nolib_filter | $localization_filter > "$pkgdir/$file"
					unix2dos "$pkgdir/$file"
				else
					$cp "$topdir/$file" "$pkgdir/$dir"
				fi
				echo "Copied: $file"
			fi
		fi
	done
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

# Queue for external checkouts.
external_dir=
external_uri=
external_tag=

checkout_queued_external() {
	if [ -n "$external_dir" -a -n "$external_uri" ]; then
		$mkdir -p "$pkgdir/$external_dir"
		echo "Getting checkout for $external_uri"
		case $external_uri in
		git:*|http://git*|https://git*)
			if [ -n "$external_tag" -a "$external_tag" != "latest" ]; then
				$git clone --branch "$external_tag" "$external_uri" "$pkgdir/$external_dir"
			else
				$git clone "$external_uri" "$pkgdir/$external_dir"
			fi
			$find "$pkgdir/$external_dir" -name .git -print | while IFS='' read -r dir; do
				$rm -fr "$dir"
			done
			;;
		svn:*|http://svn*|https://svn*)
			if [ -n "$external_tag" -a "$external_tag" != "latest" ]; then
				echo "Warning: SVN tag checkout for \`\`$external_tag'' must be given in the URI."
			fi
			$svn checkout "$external_uri" "$pkgdir/$external_dir"
			$find "$pkgdir/$external_dir" -name .svn -print | while IFS='' read -r dir; do
				$rm -fr "$dir"
			done
			;;
		*)
			echo "Unknown external: $external_uri" >&2
			;;
		esac
	fi
	# Clear the queue.
	external_dir=
	external_uri=
	external_tag=
}

# Second scan of .pkgmeta to perform pre-move-folders actions.
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
					if [ -z "$skip_externals" -a -z "$nolib" ]; then
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
					fi
					;;
				esac
				;;
			esac
			;;
		esac
	done < "$topdir/.pkgmeta"
fi

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
	change_string_underline=`echo "$change_string" | sed -e "s/./-/g"`
	project_string="$project $version"
	project_string_underline=`echo "$project_string" | sed -e "s/./=/g"`
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

# Third scan of .pkgmeta to perform move-folders actions.
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

# Creating the final zipfile for the addon.
if [ -z "$skip_zipfile" ]; then
	archive="$releasedir/$package-$version.zip"
	if [ -f "$archive" ]; then
		echo "Removing previous archive: $archive"
		$rm -f "$archive"
	fi
	( cd "$releasedir" && $zip "$archive" $contents )
fi
