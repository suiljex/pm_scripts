#/usr/bin/env bash

PMCEXECUTABLE="$(realpath $0)"
PMCROOTDIR="$(realpath $(dirname $0))"

MD="mkdir --parents"
CF="touch"
RM="rm -rf"
CP="cp -r"
MV="mv"
VOID="/dev/null"

make clean 1> ${VOID} 2> ${VOID}
git gc 1> ${VOID} 2> ${VOID}

exit 0
