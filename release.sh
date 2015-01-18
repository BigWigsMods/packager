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
mkdir=mkdir
mv=mv
pwd=pwd
rm=rm
sed=sed

# Non-POSIX tools.
git=git
svn=svn
zip=zip

# pkzip wrapper for 7z.
sevenzip=7z
zip() {
	archive="$1"; shift
	$sevenzip a -tzip $archive "$@"
}

unix2dos() {
	$sed -i "s/$/\r/" "$1"
}

# Variables set via options.
project=
topdir=
releasedir=
overwrite=
skip_externals=
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
	echo "Usage: release.sh [-eoz] [-n name] [-r releasedir] [-t topdir]" >&2
	echo "  -e               Skip checkout of external repositories." >&2
	echo "  -n name          Set the name of the addon." >&2
	echo "  -o               Keep existing package directory; just overwrite contents." >&2
	echo "  -r releasedir    Set directory containing the package directory. Defaults to \`\`\$topdir/release''." >&2
	echo "  -t topdir        Set top-level directory of Git checkout.  Defaults to \`\`$topdir''." >&2
	echo "  -z               Skip zipfile creation." >&2
}

# Process command-line options
while getopts ":eon:r:t:z" opt; do
	case $opt in
	e)
		# Skip checkout of external repositories.
		skip_externals=true
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
	result=`echo "${rtag#v}" | $sed -e "s/[0-9.]*//"`
	if [ -z "$result" ]; then
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
changelog_markup=text
enable_nolib_creation="not supported"
ignore=
license="LICENSE.txt"
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

# Queue for external checkouts.
external_dir=
external_uri=
external_tag=

checkout_queued_external() {
	if [ -n "$external_dir" -a -n "$external_uri" ]; then
		$mkdir -p "$pkgdir/$external_dir"
		echo "Getting checkout for $external_uri"
		case $external_uri in
		git:*)
			$git clone "$external_uri" "$pkgdir/$external_dir"
			$find "$pkgdir/$external_dir" -name .git -print | while IFS='' read -r dir; do
				$rm -fr "$dir"
			done
			;;
		svn:*)
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

# First scan of .pkgmeta to set variables.
if [ -f "$topdir/.pkgmeta" ]; then
	while IFS='' read -r line; do
		case $line in
		[!\ ]*:*)
			# Split $line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$line"
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
			line=${line#"${line%%[! ]*}"}	# trim leading whitespace
			case $line in
			"- "*)
				# Get the YAML list item.
				yaml_listitem "$line"
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
				# Split $line into a $yaml_key, $yaml_value pair.
				yaml_keyvalue "$line"
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

# Copy files from working directory into the package directory.
# Prune away any files in the .git and release directories.
echo "Copying files into \`\`$pkgdir'':"
$find "$topdir" -name .git -prune -o -name "${releasedir#$topdir/}" -prune -o -print | while read file; do
	file=${file#$topdir/}
	if [ "$file" != "$topdir" -a -f "$topdir/$file" ]; then
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
		# Copy any unignored files into $pkgdir.
		if [ -z "$ignored" ]; then
			dir=${file%/*}
			if [ "$dir" != "$file" ]; then
				$mkdir -p "$pkgdir/$dir"
			fi
			# Check if the file matches a pattern for keyword replacement.
			keyword="*.lua:*.md:*.toc:*.xml"
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
			if [ -n "$replaced" -a -n "$version" ]; then
				$sed -b "s/@project-version@/$version/g" "$topdir/$file" > "$pkgdir/$file"
				if $cmp -s "$topdir/$file" "$pkgdir/$file"; then
					echo "Copied: $file"
				else
					echo "Replaced repository keywords: $file"
				fi
			else
				$cp "$topdir/$file" "$pkgdir/$dir"
				echo "Copied: $file"
			fi
		fi
	fi
done

# Create a default license if one doesn't exist.
if [ -n "$license" -a ! -f "$pkgdir/$license" ]; then
	echo "All Rights Reserved." > "$pkgdir/$license"
	unix2dos "$pkgdir/$license"
fi

# Second scan of .pkgmeta to perform actions.
if [ -f "$topdir/.pkgmeta" ]; then
	while IFS='' read -r line; do
		case $line in
		[!\ ]*:*)
			# Started a new section, so checkout any queued externals.
			checkout_queued_external
			# Split $line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$line"
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key
			;;
		" "*)
			line=${line#"${line%%[! ]*}"}	# trim leading whitespace
			case $line in
			"- "*)
				;;
			*:*)
				# Split $line into a $yaml_key, $yaml_value pair.
				yaml_keyvalue "$line"
				case $pkgmeta_phase in
				externals)
					if [ -z "$skip_externals" ]; then
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

# Find the name of the project if unset.
if [ -z "$project" ]; then
	# Parse the TOC file if it exists for the title of the project.
	if [ -f "$topdir/$package.toc" ]; then
		while read line; do
			case $line in
			"## Title: "*)
				project=${line#"## Title: "}
				;;
			esac
		done < "$topdir/$package.toc"
	fi
fi
# Default to the name of the package directory.
: ${project:="$package"}

# Create changelog of commits since the previous release tag.
if [ -n "$version" ]; then
	if [ -z "$changelog" ]; then
		changelog="CHANGELOG.txt"
	fi
	if [ -n "$rtag" ]; then
		echo "Generating changelog of commits since $rtag into $changelog."
		change_string="Changes from version $rtag:"
		git_commit_range="$rtag..HEAD"
	else
		echo "Generating changelog of commits into $changelog."
		change_string="All changes:"
		git_commit_range=
	fi
	if [ -n "$version" ]; then
		project_string="$project $version"
	else
		project_string="$project (unreleased)"
	fi
	$cat > "$pkgdir/$changelog" << EOF
$project_string

$change_string

EOF
	$git log $git_commit_range --pretty=format:"- %B" >> "$pkgdir/$changelog"
	unix2dos "$pkgdir/$changelog"
fi

# Creating the final zipfile for the addon.
if [ -z "$skip_zipfile" ]; then
	if [ -n "$version" ]; then
		archive="$releasedir/$package-$version.zip"
	else
		archive="$releasedir/$package-unreleased.zip"
	fi
	if [ -f "$archive" ]; then
		echo "Removing previous archive: $archive"
		$rm -f "$archive"
	fi
	( cd "$releasedir" && $zip "$archive" $contents )
fi
