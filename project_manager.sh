#!/bin/bash

PMEXECUTABLE="$(realpath $0)"
PMROOTDIR="$(realpath $(dirname $0))"
PMDBDIR=".pm_db"
PROJINFO="projects.info"
DBID="db.id"
PMCS="pm_clean.sh"

MD="mkdir --parents"
CF="touch"
RM="rm -rf"
CP="cp -r"
MV="mv"
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
  cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -w "$1"
  RESULT=$?
  if [ ${RESULT} -eq 0 ]
  then
    return 1
  fi
  
  return 0
}

check_path()
{
  cut --delimiter=':' --fields=2 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -w "$1"
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
  if [ -f "${PMROOTDIR}/${PMDBDIR}/${DBID}" ]
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
}

add_project()
{
  if [ ${VERBOSE} -ge 1 ]
  then
    echo "Добавление проекта:" $1 $2
  fi
  
  PROJNAME=$1
  PROJLOCATION=$(realpath --relative-to="${PMROOTDIR}" "$2")
  check_name ${PROJNAME}
  RESULT=$?
  if [ ${RESULT} -eq 1 ]
  then
    report_message "ERROR: Проект с таким именем уже существует!"
    return 1
  fi
  
  check_path ${PROJLOCATION}
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
  tar cfz "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.gz" --directory "${TEMPDIR}" "$(basename "${PROJLOCATION}")"
  ${RM} "${TEMPDIR}"
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
  ${CP} ${LASTCOPY} "${PMROOTDIR}"
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
    echo "Импорт хранилища."
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
  echo "Импортируется хранилище              ${IDIMPORT}"
  if [ -f "${PMROOTDIR}/${PMDBDIR}/${DBID}" ]
  then
    IDCUR=$(cat "${PMROOTDIR}/${PMDBDIR}/${DBID}")
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
}

show_help()
{
  printf "Менежджер проектов $0\n"
  printf "Использование:\n"
  printf "\t$0 [-h]\n"
  printf "\t$0 --init\n"
  printf "\t$0 -a -p <путь к проекту> [-n <название проекта>]\n"
  printf "\t$0 -d -n <название проекта>\n"
  printf "\t$0 -s -n <название проекта> [--skip-clear]\n"
  printf "\t$0 -l -n <название проекта>\n"
  printf "\t$0 -e -n <название проекта>\n"
  printf "\t$0 --save-all [--skip-clear]\n"
  printf "\t$0 --load-all\n"
  printf "\t$0 --export-db\n"
  printf "\t$0 --import-db\n"
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
  printf "\t\t--save-all - Добавить текущие версии всех проектов в хранилище\n"
  printf "\t\t--load-all - Развернуть последние версии проектов из хранилища\n"
  printf "\t\t--export-db - Экспортировать хранилище\n"
  printf "\t\t--import-db - Импортировать хранилище\n"
}

print_debug()
{
  if [ ${VERBOSE} -lt 2 ]
  then
    return 1
  fi
  
  echo "Параметры " $0
  echo "verbose:  " ${VERBOSE}
  echo "yes:      " ${YES}
  echo "skip-clear" ${SKIPPMCS}
  echo "alias:    " ${ALIAS}
  echo "path:     " ${LOCATION}
  echo "COMMAND:  " ${COMMAND}
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
  YES=0
  VERBOSE=0
  SKIPPMCS=0
  
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
      -y|--yes)       # Takes an option argument;
        YES=1
        ;;
      --skip-clear)       # Takes an option argument;
        SKIPPMCS=1
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
      
      add_project ${ALIAS} ${LOCATION}
      return $?
      ;;
    delete)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      del_project ${ALIAS}
      return $?
      ;;
    save)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      save_project ${ALIAS}
      return $?
      ;;
    load)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      
      load_project ${ALIAS}
      return $?
      ;;
    save-all)
      PROJECTNAMES="$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | sort)"
      for PNAME in ${PROJECTNAMES}
      do
        save_project ${PNAME}
      done
      return 0
      ;;
    load-all)
      PROJECTNAMES="$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | sort)"
      for PNAME in ${PROJECTNAMES}
      do
        load_project ${PNAME}
      done
      return 0
      ;;
    export)
      if [ "${ALIAS}" == "" ]
      then
        report_message "ERROR: Не указано название проекта"
        return 1
      fi
      export_project ${ALIAS}
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
      
      import_db ${LOCATION}
      return $?
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
if [ ${RESULT} -ne 0 ] && [ ! "${COMMAND}" == "init" ]
then
  report_message "ERROR: Хранилище не инициализировано или повреждено!"
  exit 1
fi

execute_comand

exit $?
