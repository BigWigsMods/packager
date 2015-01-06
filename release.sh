#!/bin/sh
#
# Generate a zippable addon directory from a Git checkout.
#
# Usage: release.sh [-ez]
#

# Process command-line options
while getopts ":ez" opt; do
	case $opt in
	e)
		# Skip checkout of external repositories.
		skip_externals=true
		;;
	z)
		# Skip generating the zipfile.
		skip_zipfile=true
		;;
	\?)
		echo "Usage: release.sh [-ez]" >&2
		echo "  -e    Skip checkout of external repositories." >&2
		echo "  -z    Skip zipfile creation." >&2
		exit 1
		;;
	esac
done

# Path to root of Git checkout.
topdir=..
# Path to directory containing the generated addon.
releasedir=$topdir/release
# Project name.
project="Ovale Spell Priority"
# Colon-separated list of patterns of files to be ignored when copying files.
ignore=".*:tmp/*"

# Get the tag for the HEAD.
tag=`git describe HEAD --abbrev=0`
# Find the previous release tag.
rtag=`git describe HEAD~1 --abbrev=0`
while true; do
	case $rtag in
	[0-9].[0-9]) break ;;
	[0-9].[0-9].[0-9]) break ;;
	[0-9].[0-9].[0-9][0-9]) break ;;
	[0-9].[0-9].[0-9][0-9][0-9]) break ;;
	[0-9].[0-9][0-9]) break ;;
	[0-9].[0-9][0-9].[0-9]) break ;;
	[0-9].[0-9][0-9].[0-9][0-9]) break ;;
	[0-9].[0-9][0-9].[0-9][0-9][0-9]) break ;;
	esac
	rtag=`git describe $rtag~1 --abbrev=0`
done
echo "Previous release tag: $rtag"
# If the current and previous tags match, then the HEAD is not tagged.
if [ "$tag" = "$rtag" ]; then
	tag=
fi

# Version number.
version="$tag"
if [ -z "$version" ]; then
	version=`git describe HEAD`
fi

# Simple .pkgmeta processor.
while read line; do
	case ${line} in
	package-as:*)
		phase=${line%%:*}
		package=${line#*: }
		pkgdir=$releasedir/$package
		if [ -d $pkgdir ]; then
			echo "Removing previous package directory: $pkgdir"
			rm -fr $pkgdir
		fi
		mkdir -p $pkgdir
		;;
	externals:*)
		phase=${line%%:*}
		;;
	ignore:*)
		phase=${line%%:*}
		;;
	manual-changelog:*)
		phase=${line%%:*}
		changelog=${line#*: }
		;;
	filename:*)
		if [ "$phase" = "manual-changelog" ]; then
			changelog=${line#*: }
		fi
		;;
	*git*|*svn*)
		if [ "$phase" = "externals" -a -z "$skip_externals" ]; then
			dir=${line%%:*}
			uri=${line#*: }
			mkdir -p $pkgdir/$dir
			case $uri in
			git:*)
				echo "Getting checkout for $uri"
				git clone $uri $pkgdir/$dir
				;;
			svn:*)
				echo "Getting checkout for $uri"
				svn checkout $uri $pkgdir/$dir
				;;
			esac
		fi
		;;
	*"- "*)
		if [ "$phase" = "ignore" ]; then
			pattern=${line#*- }
			if [ -d "../$pattern" ]; then
				pattern="$pattern/*"
			fi
			if [ -z "$ignore" ]; then
				ignore="$pattern"
			else
				ignore="$ignore:$pattern"
			fi
		fi
		;;
	esac
done < ../.pkgmeta
find $pkgdir -name .git -print -o -name .svn -print | xargs rm -fr

# Copy files from working directory into the package directory.
find $topdir -name .git -prune -o -name release -prune -o -print | while read file; do
	file=${file#$topdir/}
	if [ "$file" != "$topdir" -a -f "$topdir/$file" ]; then
		# Check if the file should be ignored.
		list="$ignore:"
		ignored=
		while [ -n "$list" ]; do
			pattern=${list%%:*}
			list=${list#*:}
			case $file in
			$pattern)
				ignored=true
				break
				;;
			esac
		done
		if [ -z "$ignored" ]; then
			dir=${file%/*}
			if [ "$dir" != "$file" ]; then
				mkdir -p $pkgdir/$dir
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
				sed -b "s/@project-version@/$version/g" $topdir/$file > $pkgdir/$file
				if cmp -s $topdir/$file $pkgdir/$file; then
					echo "Copied: $file"
				else
					echo "Replaced repository keywords: $file"
				fi
			else
				cp $topdir/$file $pkgdir/$dir
				echo "Copied: $file"
			fi
		fi
	fi
done

# Create changelog of commits since the previous release tag.
if [ -z "$changelog" ]; then
	changelog="CHANGELOG.txt"
fi
echo "Generating changelog of commits since $rtag into $changelog."
cat > $pkgdir/$changelog << EOF
$project $version

Changes from version $rtag:

EOF
git log $rtag..HEAD --pretty=format:"- %B" >> $pkgdir/$changelog

# Creating the final zipfile for the addon using 7z.
if [ -z "$skip_zipfile" ]; then
	7z a -tzip $releasedir/$package-$version.zip $pkgdir
fi
