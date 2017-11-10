#! /bin/bash

infile=${1:-ncurses.env}

outfile=$(basename $infile .env).vars
cat << EOF > $outfile
#
# DO NOT EDIT --- this file was generated automatically from $infile"
#
# This file is meant to be sourced in a shell script to access all
# Yocto variables defined for a pakage
# 
declare -A yocto_vars
declare -A yocto_functions
declare -A yocto_python_functions
EOF

sedscript=/tmp/script.$$.sed
cat << \EOF > $sedscript
1,10d
:x
/\\$/{
N
bx
}
/^#/d
/^unset /d
s/^export //
s/^[ \t]*\([^= \t][^=]*[^= \t]\)[ \t]*=[ \t]*/yocto_vars["\1"]=/
/^python[ \t]\+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*()[ \t]*{$/{
:y
/\nNone[ \t]*}[ \t]*$/d
/\n}[ \t]*$/!{
N
by
}
s/'/'"'"'/g
s/^python[ \t]\+\([^( \t]\+\)[ \t]*()[ \t]*/yocto_python_functions["\1"]='/
s/[ \t]*$/'/
}
/^[a-zA-Z_][a-zA-Z0-9_]*[ \t]*()[ \t]*{$/{
:z
/\nNone[ \t]*}[ \t]*$/d
/\n}[ \t]*$/!{
N
bz
}
s/'/'"'"'/g
s/^\([^( \t]\+\)[ \t]*()[ \t]*/yocto_functions["\1"]='/
s/[ \t]*$/'/
}
EOF
sed -f $sedscript $infile >> $outfile
rm -f $sedscript

# construct the list of included classes and add it to the output file
yocto_classes=
for class in $(sed -n -e 's/^.*\/\([^/]\+\)\.bbclass.*$/\1/p' $infile | sort | uniq); do
	yocto_classes="$yocto_classes $class"
done
echo "yocto_classes='$yocto_classes'" >> $outfile

