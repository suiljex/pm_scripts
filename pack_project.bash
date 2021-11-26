#!/usr/bin/env bash

MD="mkdir --parents"
CF="touch"
RM="rm -rf"
CP="cp -ra"
MV="mv"
VOID="/dev/null"
GEN32CHAR="cat /dev/urandom | tr -cd 'A-Z0-9' | head -c 8"
TIMESTAMP="date +%Y.%m.%d-%H.%M.%S"

PPEXECUTABLE="$(realpath $0)"
PPROOTDIR="$(realpath $(dirname $0))"

TEMPDIR="/tmp/$(eval ${GEN32CHAR})"
PROJNAME=$(basename ${PPROOTDIR})
WORKINGDIR="${TEMPDIR}/${PROJNAME}"

TARNAME="${PROJNAME}_$(eval ${TIMESTAMP})"

${MD} "${TEMPDIR}"
${CP} "${PPROOTDIR}" "${TEMPDIR}"

(cd "${WORKINGDIR}" && make clean 1> ${VOID} 2> ${VOID})
(cd "${WORKINGDIR}" && git gc 1> ${VOID} 2> ${VOID})
(cd "${WORKINGDIR}" && ${RM} $(basename ${PPEXECUTABLE}) 1> ${VOID} 2> ${VOID})
(cd "${WORKINGDIR}" && ${RM} cmake-build* 1> ${VOID} 2> ${VOID})
(cd "${WORKINGDIR}" && ${RM} *.pro.user 1> ${VOID} 2> ${VOID})
(cd "${WORKINGDIR}" && ${RM} CMakeLists.txt 1> ${VOID} 2> ${VOID})
(cd "${WORKINGDIR}" && ${RM} .idea 1> ${VOID} 2> ${VOID})
(cd "${WORKINGDIR}" && ${RM} "${PROJNAME}_"*".tar.gz" 1> ${VOID} 2> ${VOID})

tar cfz "${PPROOTDIR}/${TARNAME}.tar.gz" --directory="${TEMPDIR}" "${PROJNAME}"

${RM} "${TEMPDIR}"

exit 0
