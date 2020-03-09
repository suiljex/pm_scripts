#!/usr/bin/env bash

PMEXECUTABLE="$(realpath "$0")"
PMROOTDIR="$(realpath "$(dirname "$0")")"
PMDBDIR=".pm_db"
PROJINFO="projects.info"
DBID="db.id"
PMCS="pm_clean.bash"

MD="mkdir --parents"
CF="touch"
RM="rm --recursive --force"
CP="cp --recursive --preserve=mode,ownership,timestamps"
MV="mv"
CD="cd"
MERGE="rsync --archive --ignore-existing"
VOID="/dev/null"
GEN32CHAR="cat /dev/urandom | tr -cd 'a-z0-9' | head -c 32"
TIMESTAMP="date +%Y.%m.%d-%H.%M.%S"

confirm_choice()
{
  if [ ${YES} -eq 1 ]
  then 
    return 0
  fi
  
  TEXT="Продолжить? [д/Н] "
  if [ ! "$1" == "" ]
  then 
    TEXT="$1 [д/Н] "
  fi
  
  read -p "${TEXT}" -r
  #echo
  if [ "$REPLY" == "Y" ] || [ "$REPLY" == "y" ] || [ "$REPLY" == "Д" ] || [ "$REPLY" == "д" ]
  then
    return 0
  fi
  
  return 1
}

report_message()
{
  printf '%s\n' "$1" >&2
}

check_name()
{
  cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -w "$1" 1> ${VOID} 2> ${VOID}
  RESULT=$?
  if [ ${RESULT} -eq 0 ]
  then
    return 1
  fi
  
  return 0
}

check_path()
{
  cut --delimiter=':' --fields=2 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -w "$1" 1> ${VOID} 2> ${VOID}
  RESULT=$?
  if [ ${RESULT} -eq 0 ]
  then
    return 1
  fi
  
  if [ ! -d "${PMROOTDIR}/$1" ]
  then
    return 2
  fi
  
  return 0
}

check_pm_db()
{
  if [ ! -f "${PMROOTDIR}/${PMDBDIR}/${DBID}" ] || [ ! -f "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" ]
  then
    return 1
  fi
  
  CTOTAL=$(sort --unique "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | wc --lines)
  CNAMES=$(sort --unique "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | cut --delimiter=':' --fields=1 | sort --unique | wc --lines)
  CLOCATIONS=$(sort --unique "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | cut --delimiter=':' --fields=2 | sort --unique | wc --lines)
  
  if ! ( [ ${CTOTAL} -eq ${CNAMES} ] && [ ${CTOTAL} -eq ${CLOCATIONS} ] )
  then
    return 1
  fi
  
  return 0
}

check_merge_conflicts()
{
  CTOTAL=$(sort --unique "$1" "$2" | wc --lines)
  CNAMES=$(sort --unique "$1" "$2" | cut --delimiter=':' --fields=1 | sort --unique | wc --lines)
  CLOCATIONS=$(sort --unique "$1" "$2" | cut --delimiter=':' --fields=2 | sort --unique | wc --lines)
  
  if [ ${CTOTAL} -eq ${CNAMES} ] && [ ${CTOTAL} -eq ${CLOCATIONS} ]
  then
    return 0
  fi
  
  return 1
}

init_pm_db()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Инициализация хранилища"
  fi
  
  if [ -f "${PMROOTDIR}/${PMDBDIR}/${DBID}" ]
  then
    IDCUR=$(cat "${PMROOTDIR}/${PMDBDIR}/${DBID}")
    report_message "WARN: Уже имеется активное хранилище ${IDCUR}"
    confirm_choice "WARN: Переинициализировать хранилище?"
    RESULT=$?
    if [ ${RESULT} -ne 0 ]
    then
      report_message "WARN: Отмена!"
      return 1
    else
      ${RM} "${PMROOTDIR}/${PMDBDIR}"
    fi
  fi
  
  ${MD} "${PMROOTDIR}/${PMDBDIR}"
  NEWID=$(eval ${GEN32CHAR})
  echo ${NEWID} > "${PMROOTDIR}/${PMDBDIR}/${DBID}"
  ${CF} "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Инициализировано хранилище ${NEWID}"
  fi
}

add_project()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Добавление проекта:" $1 $2
  fi
  
  PROJNAME=$1
  PROJLOCATION=$(realpath --relative-to="${PMROOTDIR}" "$2")
  check_name "${PROJNAME}"
  RESULT=$?
  if [ ${RESULT} -eq 1 ]
  then
    report_message "ERROR: Проект с таким именем уже существует!"
    return 1
  fi
  
  check_path "${PROJLOCATION}"
  RESULT=$?
  if [ ${RESULT} -eq 1 ]
  then
    report_message "ERROR: Проект с таким путем уже существует!"
    return 1
  elif [ ${RESULT} -eq 2 ]
  then
    report_message "ERROR: Директория $2 не существует!"
    return 1
  fi

  echo "${PROJNAME}:${PROJLOCATION}:" >> "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  ${MD} "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}"
}

del_project()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Удаление проекта:" $1
  fi
  
  PROJNAME=$1

  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    report_message "ERROR: Проекта с таким именем не существует!"
    return 1
  fi
  
  sed --in-place --expression="${LINENUM}d" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  ${RM} "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}"
}

change_name()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Изменение названия проекта:" $1 "на" $2
  fi
  
  PROJNAME=$1
  NEWNAME=$2
  
  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    report_message "ERROR: Проекта с таким именем не существует!"
    return 1
  fi
  
  check_name "${NEWNAME}"
  RESULT=$?
  if [ ${RESULT} -eq 1 ]
  then
    report_message "ERROR: Проект с таким именем уже существует!"
    return 1
  fi
  
  ESCAPEDPROJNAME=$(echo "${PROJNAME}" | sed --expression='s/[]\/$*.^[]/\\&/g')
  sed --in-place --expression="s/^${ESCAPEDPROJNAME}:/${NEWNAME}:/g" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  
  for FNAME in "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/${PROJNAME}"_*
  do 
    TEMPNAME="$(basename "${FNAME}")"
    ${MV} "${FNAME}" "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/${NEWNAME}${TEMPNAME#${PROJNAME}}"
  done
  
  ${MV} "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}" "${PMROOTDIR}/${PMDBDIR}/${NEWNAME}"
}

show_project()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Показ содержимого хранилища проекта:" $1
  fi
  
  PROJNAME=$1

  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    report_message "ERROR: Проекта с таким именем не существует!"
    return 1
  fi
  
  PROJLOCATION="$(sed --quiet --expression="${LINENUM}p" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | cut --delimiter=':' --fields=2)"
  PROJLOCATION="${PMROOTDIR}/${PROJLOCATION}"
  
  printf "%s\n" "Проект: ${PROJNAME}"
  printf "%s\n" "Путь:   ${PROJLOCATION}"
  
  if [ ${VERBOSE} -ge 1 ]
  then
    printf "%s\n" "Содержимое:"
    ls -lah "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}" | awk '{print $9, $5}' | column -t
  fi
}

save_project()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Сохранение проекта:" $1
  fi
  
  PROJNAME=$1

  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    report_message "ERROR: Проекта с таким именем не существует!"
    return 1
  fi
  
  PROJLOCATION="$(sed --quiet --expression="${LINENUM}p" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | cut --delimiter=':' --fields=2)"
  PROJLOCATION="${PMROOTDIR}/${PROJLOCATION}"
  if [ ! -d "${PROJLOCATION}" ]
  then
    report_message "ERROR: Директория ${PROJLOCATION} не существует!"
    return 1
  fi
  
  if [ -d "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/" ]
  then
    LASTCOPY="${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/$(ls "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/" | sort | tail --lines=1)"
  fi
  
  TEMPDIR="/tmp/${PROJNAME}_$(eval ${GEN32CHAR})"
  ${MD} "${TEMPDIR}"
  ${CP} "${PROJLOCATION}" "${TEMPDIR}"
  
  if [ -x "${TEMPDIR}/$(basename "${PROJLOCATION}")/${PMCS}" ] && [ ${SKIPPMCS} -eq 0 ]
  then
    eval "${TEMPDIR}/$(basename "${PROJLOCATION}")/${PMCS}"
  elif [ ${VERBOSE} -ge 1 ]
  then
    echo "Пропуск выполнения скрипта отчиски проекта"
  fi
  
  TARNAME="${PROJNAME}_$(eval ${TIMESTAMP})"
  ${MD} "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}"
  tar cfJ "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.xz" --directory "${TEMPDIR}" "$(basename "${PROJLOCATION}")"
  ${RM} "${TEMPDIR}"

  if [ ${SKIPSIMILAR} -eq 1 ] && [ -f "${LASTCOPY}" ]
  then
    NEWCOPY="${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/$(ls "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/" | sort | tail --lines=1)"
    diff ${LASTCOPY} ${NEWCOPY} 1> ${VOID} 2> ${VOID}
    RESULT=$?
    if [ ${RESULT} -eq 0 ]
    then
      ${RM} "${NEWCOPY}"
    fi
  fi
}

load_project()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Развертывание проекта:" $1
  fi
  
  PROJNAME=$1
  
  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    report_message "ERROR: Проекта с таким именем не существует!"
    return 1
  fi
  
  PROJLOCATION="$(sed --quiet --expression="${LINENUM}p" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | cut --delimiter=':' --fields=2)"
  PROJLOCATION="${PMROOTDIR}/${PROJLOCATION}"
  if [ -d "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/" ]
  then
    LASTCOPY="${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/$(ls "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/" | sort | tail --lines=1)"
  fi
  
  if [ "${LASTCOPY}" == "" ]
  then
    report_message "ERROR: В хранилище нет версий проекта с таким именем!"
    return 1
  fi
  
  if [ -d "${PROJLOCATION}" ]
  then 
    report_message "WARN: Проект с таким именем уже развернут!"
    confirm_choice "WARN: Заменить текущий развернутый проект на версию из хранилища?"
    RESULT=$?
    if [ ${RESULT} -ne 0 ]
    then
      report_message "WARN: Отмена!"
      return 1
    else
      ${RM} "${PROJLOCATION}"
    fi
  fi
  
  TEMPDIR="/tmp/${PROJNAME}_$(eval ${GEN32CHAR})"
  ${MD} "${TEMPDIR}"
  tar xfz "${LASTCOPY}" --directory "${TEMPDIR}"
  ${MV} "${TEMPDIR}/$(basename "${PROJLOCATION}")" "$(dirname "${PROJLOCATION}")"
  ${RM} "${TEMPDIR}"
}

export_project()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Экспорт проекта:" $1
  fi
  
  PROJNAME=$1
  
  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    report_message "ERROR: Проекта с таким именем не существует!"
    return 1
  fi
  
  LASTCOPY="${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/$(ls "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/" | sort | tail --lines=1)"
  if [ "${LASTCOPY}" == "" ]
  then
    report_message "ERROR: Проекта с таким именем нет в хранилище!"
    return 1
  fi
  ${CP} "${LASTCOPY}" "${PMROOTDIR}"
}

export_db()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Экспорт хранилища."
  fi
  
  TARNAME="projectmanagerdb_$(eval ${TIMESTAMP})"
  tar cf "${TARNAME}.tar" --directory "${PMROOTDIR}" "$(basename "${PMROOTDIR}/${PMDBDIR}")"
}

import_db()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Импорт хранилища" $1
  fi
  
  TARNAME=$1
  TEMPDIR="/tmp/${PMROOTDIR}_$(eval ${GEN32CHAR})"
  ${MD} "${TEMPDIR}"
  tar xf "${TARNAME}" --directory "${TEMPDIR}" "${PMDBDIR}/${DBID}" 2> ${VOID}
  RESULT=$?
  if [ ${RESULT} -ne 0 ]
  then
    ${RM} "${TEMPDIR}"
    report_message "ERROR: Неверный формат"
    return 1
  fi
  
  IDIMPORT=$(cat "${TEMPDIR}/${PMDBDIR}/${DBID}")
  ${RM} "${TEMPDIR}"
  if [ -f "${PMROOTDIR}/${PMDBDIR}/${DBID}" ]
  then
    IDCUR=$(cat "${PMROOTDIR}/${PMDBDIR}/${DBID}")
    report_message "WARN: Импортируется хранилище        ${IDIMPORT}"
    report_message "WARN: Уже имеется активное хранилище ${IDCUR}"
    confirm_choice "WARN: Заменить текущее хранилище импортируемым?"
    RESULT=$?
    if [ ${RESULT} -ne 0 ]
    then
      report_message "WARN: Отмена!"
      return 1
    else
      ${RM} "${PMROOTDIR}/${PMDBDIR}"
    fi
  fi
  
  tar xf "${TARNAME}" --directory "${PMROOTDIR}"
  
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Импортировано хранилище ${IDIMPORT}"
  fi
}

merge_db()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Слияние хранилища" $1
  fi
  
  TARNAME=$1
  TEMPDIR="/tmp/${PMROOTDIR}_$(eval ${GEN32CHAR})"
  ${MD} "${TEMPDIR}"
  tar xf "${TARNAME}" --directory "${TEMPDIR}" "${PMDBDIR}/${DBID}" "${PMDBDIR}/${PROJINFO}" 2> ${VOID}
  RESULT=$?
  if [ ${RESULT} -ne 0 ]
  then
    ${RM} "${TEMPDIR}"
    report_message "ERROR: Неверный формат"
    return 1
  fi
  
  IDMERGE=$(cat "${TEMPDIR}/${PMDBDIR}/${DBID}")
  IDCUR=$(cat "${PMROOTDIR}/${PMDBDIR}/${DBID}")
  
  printf "Сливаемые хранилища:\n"        
  printf "Текущее ${IDCUR}\n"
  printf "Новое   ${IDMERGE}\n"
  
  check_merge_conflicts "${TEMPDIR}/${PMDBDIR}/${PROJINFO}" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  RESULT=$?
  if [ ${RESULT} -ne 0 ]
  then
    ${RM} "${TEMPDIR}"
    report_message "ERROR: Конфликт слияния!"
    return 1
  fi
  
  confirm_choice
  RESULT=$?
  if [ ${RESULT} -ne 0 ]
  then
    report_message "WARN: Отмена!"
    ${RM} "${TEMPDIR}"
    return 1
  fi
  tar xf "${TARNAME}" --directory "${TEMPDIR}"
  
  sort --unique "${TEMPDIR}/${PMDBDIR}/${PROJINFO}" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" > "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}.temp"
  ${MV} "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}.temp" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  
  ${MERGE} "${TEMPDIR}/${PMDBDIR}/" "${PMROOTDIR}/${PMDBDIR}/"
  ${RM} "${TEMPDIR}"
}

show_help()
{
  printf "Менежджер проектов $0\n"
  printf "Использование:\n"
  printf "\t$0 [-h]\n"
  printf "\t$0 --init\n"
  printf "\t$0 -a -p <путь к проекту> [-n <название проекта>]\n"
  printf "\t$0 -d -n <название проекта>\n"
  printf "\t$0 -s -n <название проекта> [--skip-clear] [--skip-similar]\n"
  printf "\t$0 -l -n <название проекта>\n"
  printf "\t$0 -e -n <название проекта>\n"
  printf "\t$0 --save-all [--skip-clear] [--skip-similar]\n"
  printf "\t$0 --load-all\n"
  printf "\t$0 --export-db\n"
  printf "\t$0 --import-db -p <путь к проекту>\n"
  printf "\t$0 --merge-db -p <путь к проекту>\n"
  printf "\t$0 --show -n <название проекта>\n"
  printf "\t$0 --show-all\n"
  printf "\t$0 --rename <новое название проекта> -n <старое название проекта>\n"
  printf "\t\t--init - Инициализация хранилища\n"
  printf "\t\t-a, --add - Добавить проект в хранилище\n"
  printf "\t\t-d, --delete - Удалить проект из хранилища\n"
  printf "\t\t-s, --save - Добавить текущую версию проекта в хранилище\n"
  printf "\t\t-l, --load - Развернуть последнюю версию проекта из хранилища\n"
  printf "\t\t-e, --export - Выгрузить последнюю версию проекта из хранилища в корень $0\n"
  printf "\t\t-p, --path - Указать путь\n"
  printf "\t\t-n, --alias - Указать имя проекта\n"
  printf "\t\t--yes - Соглашаться со всеми запросами\n"
  printf "\t\t--skip-clear - Пропустить выполнение скрипта отчиски проекта\n"
  printf "\t\t--skip-similar - Не сохранять текущую версию, если она не отличается от предыдущей\n"
  printf "\t\t--save-all - Добавить текущие версии всех проектов в хранилище\n"
  printf "\t\t--load-all - Развернуть последние версии проектов из хранилища\n"
  printf "\t\t--export-db - Экспортировать хранилище\n"
  printf "\t\t--import-db - Импортировать хранилище\n"
  printf "\t\t--merge-db - Слить хранилище\n"
  printf "\t\t--show - Показать содержимое проекта в хранилище\n"
  printf "\t\t--show-all - Показать содержимое проектов в хранилище\n"
  printf "\t\t--rename - Изменить название проекта в хранилище\n"
}

print_debug()
{
  if [ ${VERBOSE} -lt 2 ]
  then
    return 1
  fi
  
  echo "Параметры " "$0"
  echo "verbose:     " "${VERBOSE}"
  echo "yes:         " "${YES}"
  echo "skip-clear:  " "${SKIPPMCS}"
  echo "skip-similar:" "${SKIPSIMILAR}"
  echo "alias:       " "${ALIAS}"
  echo "path:        " "${LOCATION}"
  echo "newname:     " "${NEWNAME}"
  echo "COMMAND:     " "${COMMAND}"
}

parse_command()
{
  if [ $# -lt 1 ]
  then
    show_help
    exit 1
  fi
  
  LOCATION=""
  ALIAS=""
  COMMAND=""
  NEWNAME=""
  YES=0
  VERBOSE=0
  SKIPPMCS=0
  SKIPSIMILAR=0
  
  while :; do
    case $1 in
      -h|-\?|--help)
        show_help    # Display a usage synopsis.
        exit 0
        ;;
      --init)         # Handle the case of an empty --file=
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="init"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      -p|--path)       # Takes an option argument; ensure it has been specified.
        if [ "$2" ]; then
          LOCATION=$2
          shift
        else
          report_message "ERROR: \"--path\" requires a non-empty option argument."
          return 1
        fi
        ;;
      --path=?*)
        LOCATION=${1#*=} # Delete everything up to "=" and assign the remainder.
        ;;
      --path=)         # Handle the case of an empty --file=
        report_message "ERROR: \"--path\" requires a non-empty option argument."
        return 1
        ;;
      -n|--alias)       # Takes an option argument; ensure it has been specified.
        if [ "$2" ]; then
          ALIAS=$2
          shift
        else
          report_message "ERROR: \"--alias\" requires a non-empty option argument."
          return 1
        fi
        ;;
      --alias=?*)
        ALIAS=${1#*=} # Delete everything up to "=" and assign the remainder.
        ;;
      --alias=)         # Handle the case of an empty --file=
        report_message "ERROR: \"--alias\" requires a non-empty option argument."
        return 1
        ;;
      -a|--add)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="add"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      -d|--delete)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="delete"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --rename)       # Takes an option argument; ensure it has been specified.
        if [ "$2" ]; then
          NEWNAME=$2
          COMMAND="rename"
          shift
        else
          report_message "ERROR: \"--rename\" requires a non-empty option argument."
          return 1
        fi
        ;;
      --rename=?*)
        NEWNAME=${1#*=} # Delete everything up to "=" and assign the remainder.
        COMMAND="rename"
        ;;
      --rename=)         # Handle the case of an empty --file=
        report_message "ERROR: \"--rename\" requires a non-empty option argument."
        return 1
        ;;
      -s|--save)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="save"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      -l|--load)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="load"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --save-all)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="save-all"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --load-all)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="load-all"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      -e|--export)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="export"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --export-db)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="export-db"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --import-db)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="import-db"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --merge-db)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="merge-db"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --show)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="show"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      --show-all)       # Takes an option argument;
        if [ "${COMMAND}" == "" ]
        then
          COMMAND="show-all"
        else
          report_message "ERROR: Разрешено только одно действие за раз!"
          return 1
        fi
        ;;
      -y|--yes)       # Takes an option argument;
        YES=1
        ;;
      --skip-clear)       # Takes an option argument;
        SKIPPMCS=1
        ;;
      --skip-similar)       # Takes an option argument;
        SKIPSIMILAR=1
        ;;
      -v|--verbose)
        VERBOSE=$((VERBOSE + 1))  # Each -v adds 1 to verbosity.
        ;;
      --)              # End of all options.
        shift
        break
        ;;
      -?*)
        printf "WARN: Unknown option (ignored): %s\n" "$1" >&2
        ;;
      *)               # Default case: No more options, so break out of the loop.
        break
    esac

    shift
  done
}

execute_comand()
{
  case ${COMMAND} in
    init)
      init_pm_db
      return $?
      ;;
    add)
      if [ "${LOCATION}" == "" ]
      then
        report_message "ERROR: Не указан путь к проеку"
        return 1
      fi
      
      if [ "${ALIAS}" == "" ]
      then
        ALIAS="$(basename "${LOCATION}")"
        report_message "WARN: Не указано название проекта"
        report_message "WARN: В качестве названия будет использовано: \"${ALIAS}\""
      fi
      
      add_project "${ALIAS}" "${LOCATION}"
      return $?
      ;;
    delete)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      del_project "${ALIAS}"
      return $?
      ;;
    rename)
      if [ "${ALIAS}" == "" ] || [ "${NEWNAME}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      change_name "${ALIAS}" "${NEWNAME}"
      return $?
      ;;
    save)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      save_project "${ALIAS}"
      return $?
      ;;
    load)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      load_project "${ALIAS}"
      return $?
      ;;
    save-all)
      PROJECTNAMES="$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | sort)"
      for PNAME in ${PROJECTNAMES}
      do
        save_project "${PNAME}"
      done
      return 0
      ;;
    load-all)
      PROJECTNAMES="$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | sort)"
      for PNAME in ${PROJECTNAMES}
      do
        load_project "${PNAME}"
      done
      return 0
      ;;
    export)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      export_project "${ALIAS}"
      return $?
      ;;
    export-db)
      export_db
      return $?
      ;;
    import-db)
      if [ "${LOCATION}" == "" ]
      then
        report_message "ERROR: Не указан путь к импортируемому хранилищу"
        return 1
      fi
      
      import_db "${LOCATION}"
      return $?
      ;;
    merge-db)
      if [ "${LOCATION}" == "" ]
      then
        report_message "ERROR: Не указан путь к сливаемому хранилищу"
        return 1
      fi
      
      merge_db "${LOCATION}"
      return $?
      ;;
    show)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      show_project "${ALIAS}"
      return $?
      ;;
    show-all)
      PROJECTNAMES="$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | sort)"
      for PNAME in ${PROJECTNAMES}
      do
        show_project "${PNAME}"
      done
      return 0
      ;;
    *)
      report_message "ERROR: Не указана команда"
      return 1
  esac
}

parse_command "$@"
RESULT=$?
if [ ${RESULT} -ne 0 ]
then
  exit ${RESULT}
fi

print_debug
check_pm_db
RESULT=$?
if [ ${RESULT} -ne 0 ] && [ ! "${COMMAND}" == "init" ] && [ ! "${COMMAND}" == "import-db" ] 
then
  report_message "ERROR: Хранилище не инициализировано или повреждено!"
  exit 1
fi

execute_comand

exit $?
