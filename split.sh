#!/bin/bash
# Script to split installation into tarball feeds
# - base  : items that must always be installed
# - dev   : items for development: header files, static libraries, dynamic libraries links
# - dbg   : items for delivery with debug feature unstripped
# - doc   : items for delivery with generated documentations
# - locale: items related to internationalization

here=$(pwd)
basedir=$(dirname "$0")

source $script_lib_dir/utils.sh

# Give default values to parameters (:= if null or unset, = if only unset, variables must be defined)

# Package where package install step place files
: ${installDir:=$here/_install}

# Package installation directories in installDir
: ${exec_prefix:="${prefix}"}
: ${bindir:="${exec_prefix}/bin"}
: ${sbindir:="${exec_prefix}/sbin"}
: ${libdir:="${exec_prefix}/lib"}
: ${libexecdir:="${exec_prefix}/libexec"}
: ${datarootdir:="${prefix}/share"}
: ${datadir:="${datarootdir}"}
: ${sysconfdir:="${prefix}/etc"}
: ${localstatedir:="${prefix}/var"}
: ${docdir:="${datarootdir}/doc/${package_name}"}
: ${mandir:="${datarootdir}/man"}
: ${infodir:="${datarootdir}/info"}
: ${includedir:="${prefix}/include"}
: ${localedir:="${datarootdir}/locale"}

# Build-step specific variables
package_id=$PACKAGE_ID # Can't use directly as version/revision not at the proper place for sub-packages
package_name=$PACKAGE_NAME
package_version=$PACKAGE_VERSION
package_revision=${PACKAGE_REV:-r0}
package_arch=${PACKAGE_ARCH:-all}
package_suffix="${package_version}-${package_revision}_${package_arch}"

: ${splitted_packages:=$package_name}
: ${sub_packages:="doc dev dbg locale base"}
: ${needed_subpackages:="dev dbg base"}
: ${installDir:=$here/_install}
: ${solibs:=".so.* .so-*"}
: ${solibsdev:=".so"}

: ${pattern_base:="usr/lib/engines/ usr/etc/ssl/misc/ usr/etc/ssl/ bin/ sbin/ lib/*.so-* lib/*.so.* usr/bin usr/sbin usr/lib/*.so-* usr/lib/*.so.* usr/share/bash-completion share/bash-completion usr/share/misc usr/etc/udev usr/libexec/udev usr/libexec"}
: ${pattern_locale:="share/locale/ usr/share/locale/"}
: ${pattern_dev:="lib/*.so lib/*.a lib/*.la usr/include/ usr/lib/*.so usr/lib/*.a usr/lib/*.la lib/pkgconfig usr/lib/pkgconfig usr/share/pkgconfig usr/share/aclocal share/aclocal"}
: ${pattern_dbg:="bin/.debug lib/.debug"}
: ${pattern_doc:="usr/etc/ssl/man/ share/doc usr/share/doc share/man usr/share/man share/info usr/share/info usr/share/gtk-doc"}

#doc_package_name="${package_name}-doc_${package_version}-${package_revision}"
#dev_package_name="${package_name}-dev_${package_version}-${package_revision}-${package_arch}"
#dbg_package_name="${package_name}-dbg_${package_version}-${package_revision}-${package_arch}"
#locale_package_name="${package_name}-locale_${package_version}-${package_revision}"
#base_package_name="${package_name}_${package_version}-${package_revision}-${package_arch}"

tempDir=/tmp/$package_name.$$
mkdir -p $tempDir/install
tar cf - -C $installDir . | tar xf - -C $tempDir/install
cd $tempDir/install
# Remove the fakeroot state, as it is not part of the package...
rm -f .fakeroot

# Generate in a temporary directory, before moving in feedsDir
metadataDir=$tempDir/feeds/metadata/$package_id
contentsDir=$tempDir/feeds/contents
packagesDir=$tempDir/feeds/packages
tarballsDir=$tempDir/feeds/tarballs/$package_arch
mkdir -p $contentsDir $packagesDir $tarballsDir $metadataDir

allContentsDir=$feedsDir/contents

base_bin_packages=
forced_bin_packages=
bin_sub_packages=

# Generate list of packages and package content
if [ "$splitted_packages" = "$package_name" ]; then
	splitted_packages=
	for pkg in $sub_packages; do
		if [ "$pkg" = "base" ]; then
			splitted_packages="$splitted_packages $package_name"
		else
			splitted_packages="$splitted_packages $package_name-$pkg"
		fi
	done
fi

for pkgname in $splitted_packages; do
	subpkg=${pkgname#$package_name}
	if [ -z "$subpkg" ]; then
		pkg=base
		subpkg=base
	else
		subpkg=${subpkg#-}
		pkg=${subpkg##*-}
		subpkg=${subpkg//-/_}
	fi
	pattern_name=pattern_$subpkg

	bin_package=${pkgname}_${package_suffix}
	forced=true
	if [ "$pkg" = "base" ]; then
		base_bin_packages="$base_bin_packages $bin_package"
	elif [[ " $needed_subpackages " =~ " $pkg " ]]; then
		forced_bin_packages="$forced_bin_packages $bin_package"
	elif [[ " $needed_subpackages " =~ " $bin_package " ]]; then
		forced_bin_packages="$forced_bin_packages $bin_package"
	else
		bin_sub_packages="$bin_sub_packages $bin_package"
		forced=false
	fi

	pkgTarball=${bin_package}.tar.bz2
	file_list=$contentsDir/$bin_package.list
	# Create a file with the list of files to put in the archive
	# This has the additional benefit of allowing to create empty archives if needed
	touch $file_list
	pattern="${!pattern_name}"
	if [ -n "$pattern" ]; then
		pattern=
		# Eliminate inital slashes, we want to match local files...
		set -o noglob
		for fspec in ${!pattern_name}; do
			pattern="$pattern ${fspec#/}"
		done
		set +o noglob
		for fspec in $(echo ${pattern}); do
			if [ -d $fspec ]; then
				find $fspec ! -type d >> $file_list
			elif [ -e $fspec -o -L $fspec ]; then
				echo $fspec >> $file_list
			fi
		done
	fi
	
	if [ -s "$file_list" ]; then
		echo "Generating ${pkgname} ${pkg^^} package feed: '$bin_package'"
	elif $forced; then
		echo "Force generation of empty ${pkgname} ${pkg^^} package feed: '$bin_package'"
	else
		continue
	fi

	# Generate the package description metadata and dependencies
	for spec in SUMMARY DESCRIPTION SECTION HOMEPAGE LICENSE RDEPENDS RRECOMMENDS RSUGGESTS; do
		spec_var=${spec}_$subpkg
		val=${!spec_var}
		if [ -n "$val" ]; then
			echo "$val" > $metadataDir/$bin_package.${spec,,}
		fi
	done
	
	echo "tar -cjf $tarballsDir/$pkgTarball --files-from=$file_list"
	tar -cjf $tarballsDir/$pkgTarball --files-from=$file_list
	echo $package_id > $packagesDir/$bin_package

	# Remove the packaged files so that a file is only packaged once
	for i in $(cat $file_list); do
		rm -f $i
	done
	echo ""
done

# Check that all files has been packaged
remaining_files=$(find . -type f | sed -e 's/^\.//')
if [ -n "$remaining_files" ]; then
	echo "#################################################################################################"
	echo "#"
	echo "# There are unpackaged files in package ${package_name}; please correct packaging directives"
	echo "#"
	echo "# Unpackages files are:"
	for file in $remaining_files; do
		echo "# 	$file"
	done
	echo "#"
	echo "#################################################################################################"
	rm -rf $tempDir
	exit 1
fi

# Copy package metadata definitions
 
# Finally automatically create dynamic libraries runtime dependencies
prefix="$(basename "${compiler_prefix}")"
readelf="${compiler_prefix}-readelf"
if [ ! -x "$( which "${readelf}" )" ]; then
    readelf="${prefix}-readelf"
fi
if [ ! -x "$( which "${readelf}" )" ]; then
    readelf="readelf"
fi
if [ ! -x "$( which "${readelf}" )" ]; then
    echo "Can't execute '${compiler_prefix}-readelf' nor '${prefix}-readelf' or 'readelf'"
    exit 1
fi

get_needed_libraries() {
	local bin_package="$1"
	local subpkg="$2"
	(
		for file in $(cat $contentsDir/$bin_package.list); do
		    ${readelf} -d $installDir/$file 2> /dev/null			\
		    | grep -E '\(NEEDED\)' 2> /dev/null					\
		    | sed -r -e 's/^.*Shared library:[[:space:]]+\[(.*)\]$/\1/;'
		done | sort | uniq | while read lib; do
			# Look for the package providing this library
			grep -l "/$lib\$" $contentsDir/*.list $allContentsDir/*.list
		done | sed -e 's|^.*/||' -e 's/.list//' 
		if [ -n "$subpkg" ]; then
			# sub-pkg is the last -enclosed element of the name
			subpkg=$(echo $bin_package | sed -e 's/_.*$//' -e 's/^.*-\([^-]\+\)$/\1/')
			if [ -z "$subpkg" ]; then
				echo "Malformed subpackage name: '$bin_package'"
			else
				base_package=$(echo $bin_package | sed -e "s/-${subpkg}_/_/") 
				cat $metadataDir/$base_package.auto-depends | sed -e "s/_/-${subpkg}_/"
				echo $base_package
			fi
		fi
	) | sort | uniq
}

echo "Generating ${package_name} automatic runtime dependencies"
for bin_package in $base_bin_packages $bin_sub_packages; do
	get_needed_libraries $bin_package > $metadataDir/$bin_package.auto-depends
done
for bin_package in $forced_bin_packages; do
	get_needed_libraries $bin_package subpkg > $metadataDir/$bin_package.auto-depends
done

# Now install the generated packages
echo "tar cf - -C $tempDir feeds | tar xf - -C $PLATFORM_LOC"
tar cf - -C $tempDir feeds | tar xf - -C $PLATFORM_LOC

# Clean the working area
rm -rf $tempDir
