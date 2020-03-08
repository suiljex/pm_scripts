#!/bin/bash

PMEXECUTABLE="$(realpath $0)"
PMROOTDIR="$(realpath $(dirname $0))"
PMDBDIR="pm_db"
PROJINFO="projects.info"
DBID="db.id"

MD="mkdir --parents"
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

init_pm_db()
{
  ${MD} "${PMROOTDIR}/${PMDBDIR}"
  NEWID=$(eval ${GEN32CHAR})
  echo ${NEWID} > "${PMROOTDIR}/${PMDBDIR}/${DBID}"
}

add_project()
{
  PROJNAME=$1
  PROJLOCATION=$(realpath --relative-to="${PMROOTDIR}" "$2")
  check_name ${PROJNAME}
  RESULT=$?
  if [ ${RESULT} -e 1 ]
  then
    echo "Проект с таким именем уже существует!"
    return 1
  fi
  
  check_path ${PROJLOCATION}
  RESULT=$?
  if [ ${RESULT} -e 1 ]
  then
    echo "Проект с таким путем уже существует!"
    return 1
  elif [ ${RESULT} -e 2 ]
  then
    echo "Директория $2 не существует!"
    return 1
  fi

  echo "${PROJNAME}:${PROJLOCATION}:" >> "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  ${MD} "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}"
}

del_project()
{
  PROJNAME=$1

  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    echo "Проекта с таким именем не существует!"
    return 1
  fi
  
  sed --in-place --expression="${LINENUM}d" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}"
  ${RM} "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}"
}

save_project()
{
  PROJNAME=$1

  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    echo "Проекта с таким именем не существует!"
    return 1
  fi
  
  PROJLOCATION="$(sed --quiet --expression="${LINENUM}p" "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | cut --delimiter=':' --fields=2)"
  PROJLOCATION="${PMROOTDIR}/${PROJLOCATION}"
  if [ ! -d "${PROJLOCATION}" ]
  then
    echo "Директория ${PROJLOCATION} не существует!"
    return 1
  fi
  
  TEMPDIR="/tmp/${PROJNAME}_$(eval ${GEN32CHAR})"
  ${MD} "${TEMPDIR}"
  ${CP} "${PROJLOCATION}" "${TEMPDIR}"
  #TODO call clear script
  TARNAME="${PROJNAME}_$(eval ${TIMESTAMP})"
  #echo ${TEMPDIR}/$(basename "${PROJLOCATION}")
  #echo "${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.gz"
  ${MD} "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}"
  tar cfz "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.gz" --directory "${TEMPDIR}" "$(basename "${PROJLOCATION}")"
  ${RM} "${TEMPDIR}"
  #echo $TEMPDIR
}

load_project()
{
  PROJNAME=$1
  
  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    echo "Проекта с таким именем не существует!"
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
    echo "В хранилище нет версий проекта с таким именем!"
    return 1
  fi
  
  if [ -d "${PROJLOCATION}" ]
  then 
    echo "Проект с таким именем уже развернут!"
    confirm_choice "Заменить текущий развернутый проект на версию из хранилища?"
    RESULT=$?
    if [ ${RESULT} -ne 0 ]
    then
      echo "Останов!"
      return 1
    else
      ${RM} "${PROJLOCATION}"
    fi
  fi
  
  #echo $LASTCOPY
  TEMPDIR="/tmp/${PROJNAME}_$(eval ${GEN32CHAR})"
  ${MD} "${TEMPDIR}"
  tar xfz "${LASTCOPY}" --directory "${TEMPDIR}"
  #ls  "${TEMPDIR}" | sort
  #ls  "${PROJLOCATION}" | sort
  ${MV} "${TEMPDIR}/$(basename "${PROJLOCATION}")" "$(dirname "${PROJLOCATION}")"
  #ls  "${PROJLOCATION}" | sort
  #echo $(basename "${PROJLOCATION}")
  #echo $(dirname "${PROJLOCATION}")
  
  #${CP} "${PROJLOCATION}" "${TEMPDIR}"
  #TODO call clear script
  #TARNAME="${PROJNAME}_$(eval ${TIMESTAMP})"
  #echo ${TEMPDIR}/$(basename "${PROJLOCATION}")
  #echo "${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.gz"
  #${MD} "${PMDBDIR}/${PROJNAME}"
  #tar cfz "${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.gz" -C "${TEMPDIR}" "$(basename "${PROJLOCATION}")" 2> ${VOID}
  ${RM} "${TEMPDIR}"
  #echo $TEMPDIR
}

export_project()
{
  PROJNAME=$1
  
  LINENUM=$(cut --delimiter=':' --fields=1 "${PMROOTDIR}/${PMDBDIR}/${PROJINFO}" | grep -wn "${PROJNAME}" | cut --delimiter=':' --fields=1 | head --lines=1)
  if [ "${LINENUM}" == "" ]
  then
    echo "Проекта с таким именем не существует!"
    return 1
  fi
  
  LASTCOPY="${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/$(ls "${PMROOTDIR}/${PMDBDIR}/${PROJNAME}/" | sort | tail --lines=1)"
  if [ "${LASTCOPY}" == "" ]
  then
    echo "Проекта с таким именем нет в хранилище!"
    return 1
  fi
  echo $LASTCOPY
  #TEMPDIR="/tmp/${PROJNAME}_$(eval ${GEN32CHAR})"
  #${MD} "${TEMPDIR}"
  #tar xfz "${LASTCOPY}" --directory "${TEMPDIR}"
  #ls  "${TEMPDIR}" | sort
  #ls  "${PROJLOCATION}" | sort
  ${CP} ${LASTCOPY} "${PMROOTDIR}"
  #ls  "${PROJLOCATION}" | sort
  #echo $(basename "${PROJLOCATION}")
  #echo $(dirname "${PROJLOCATION}")
  
  #${CP} "${PROJLOCATION}" "${TEMPDIR}"
  #TODO call clear script
  #TARNAME="${PROJNAME}_$(eval ${TIMESTAMP})"
  #echo ${TEMPDIR}/$(basename "${PROJLOCATION}")
  #echo "${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.gz"
  #${MD} "${PMDBDIR}/${PROJNAME}"
  #tar cfz "${PMDBDIR}/${PROJNAME}/${TARNAME}.tar.gz" -C "${TEMPDIR}" "$(basename "${PROJLOCATION}")" 2> ${VOID}
  #${RM} "${TEMPDIR}"
  #echo $TEMPDIR
}

export_db()
{
  TARNAME="pm_db_$(eval ${TIMESTAMP})"
  tar cf "${TARNAME}.tar" --directory "${PMROOTDIR}" "$(basename "${PMROOTDIR}/${PMDBDIR}")"
}

import_db()
{
  TARNAME=$1
  TEMPDIR="/tmp/${PMROOTDIR}_$(eval ${GEN32CHAR})"
  ${MD} "${TEMPDIR}"
  tar xf "${TARNAME}" --directory "${TEMPDIR}" "${PMDBDIR}/${DBID}" 2> ${VOID}
  RESULT=$?
  if [ ${RESULT} -ne 0 ]
  then
    echo "Неверный формат"
    return 1
  fi
  
  IDIMPORT=$(cat "${TEMPDIR}/${PMDBDIR}/${DBID}")
  echo "Импортируется хранилище        ${IDIMPORT}"
  if [ -f "${PMROOTDIR}/${PMDBDIR}/${DBID}" ]
  then
    IDCUR=$(cat "${PMROOTDIR}/${PMDBDIR}/${DBID}")
    echo "Уже имеется активное хранилище ${IDCUR}"
    confirm_choice "Заменить текущее хранилище импортируемым?"
    RESULT=$?
    if [ ${RESULT} -ne 0 ]
    then
      echo "Останов!"
      return 1
    else
      ${RM} "${PMROOTDIR}/${PMDBDIR}"
    fi
  fi
  
  tar xf "${TARNAME}" --directory "${PMROOTDIR}"
  
  ${RM} "${TEMPDIR}"
}

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

show_help()
{
  printf "Менежджер проектов $0\n"
  printf "Использование:\n"
  printf "\t$0 [-h]\n"
  printf "\t$0 -a -p <путь к проекту> [-n <название проекта>]\n"
  printf "\t$0 -d -n <название проекта>\n"
  printf "\t$0 -s -n <название проекта>\n"
  printf "\t$0 -l -n <название проекта>\n"
  printf "\t$0 -e -n <название проекта>\n"
  printf "\t$0 --save-all\n"
  printf "\t$0 --load-all\n"
  printf "\t$0 --export-db\n"
  printf "\t$0 --import-db\n"
  printf "\t\t-a, --add - Добавить проект в хранилище\n"
  printf "\t\t-d, --delete - Удалить проект из хранилища\n"
  printf "\t\t-s, --save - Добавить текущую версию проекта в хранилище\n"
  printf "\t\t-l, --load - Развернуть последнюю версию проекта из хранилища\n"
  printf "\t\t-e, --export - Выгрузить последнюю версию проекта из хранилища в корень $0\n"
  printf "\t\t-p, --path - Указать путь\n"
  printf "\t\t-n, --alias - Указать имя проекта\n"
  printf "\t\t--yes - Соглашаться со всеми запросами\n"
  printf "\t\t--save-all - Добавить текущие версии всех проектов в хранилище\n"
  printf "\t\t--load-all - Развернуть последние версии проектов из хранилища\n"
  printf "\t\t--export-db - Экспортировать хранилище\n"
  printf "\t\t--import-db - Импортировать хранилище\n"
}

print_debug()
{
  if [ ${VERBOSE} -eq 0 ]
  then
    return 1
  fi
  
  echo "Параметры" $0
  echo "verbose: " ${VERBOSE}
  echo "yes:     " ${YES}
  echo "alias:   " ${ALIAS}
  echo "path:    " ${LOCATION}
  echo "COMMAND: " ${COMMAND}
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
  
  while :; do
    case $1 in
        -h|-\?|--help)
            show_help    # Display a usage synopsis.
            exit 0
            ;;
        -p|--path)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
              LOCATION=$2
              shift
            else
              die 'ERROR: "--path" requires a non-empty option argument.'
            fi
            ;;
        --path=?*)
            LOCATION=${1#*=} # Delete everything up to "=" and assign the remainder.
            ;;
        --path=)         # Handle the case of an empty --file=
            die 'ERROR: "--path" requires a non-empty option argument.'
            ;;
        -n|--alias)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
              ALIAS=$2
              shift
            else
              die 'ERROR: "--alias" requires a non-empty option argument.'
            fi
            ;;
        --alias=?*)
            ALIAS=${1#*=} # Delete everything up to "=" and assign the remainder.
            ;;
        --alias=)         # Handle the case of an empty --file=
            die 'ERROR: "--alias" requires a non-empty option argument.'
            ;;
        -a|--add)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="add"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        -d|--delete)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="delete"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        -s|--save)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="save"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        -l|--load)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="load"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        --save-all)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="save-all"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        --load-all)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="load-all"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        -e|--export)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="export"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        --export-db)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="export-db"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        --import-db)       # Takes an option argument;
            if [ "${COMMAND}" == "" ]
            then
              COMMAND="import-db"
            else
              die "ERROR: Разрешено только одно действие за раз!"
            fi
            ;;
        -y|--yes)       # Takes an option argument;
            YES=1
            ;;
        -v|--verbose)
            VERBOSE=$((verbose + 1))  # Each -v adds 1 to verbosity.
            ;;
        --)              # End of all options.
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
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
          add)
                if [ "${LOCATION}" == "" ]
                then
                  echo "Не указан путь к проеку"
                  return 1
                fi
                
                if [ "${ALIAS}" == "" ]
                then
                  ALIAS="$(basename "${LOCATION}")"
                  echo "Не указано название проекта"
                  echo "В качестве названия будет использовано: \"${ALIAS}\""
                fi
                
                add_project ${ALIAS} ${LOCATION}
                return $?
              ;;
          delete)
                if [ "${ALIAS}" == "" ]
                then
                  echo "Не указано название проекта"
                  return 1
                fi
                
                del_project ${ALIAS}
                return $?
              ;;
          save)
                if [ "${ALIAS}" == "" ]
                then
                  echo "Не указано название проекта"
                  return 1
                fi
                
                save_project ${ALIAS}
                return $?
              ;;
          load)
                if [ "${ALIAS}" == "" ]
                then
                  echo "Не указано название проекта"
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
                  echo "Не указано название проекта"
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
                  echo "Не указан путь к импортируемому хранилищу"
                  return 1
                fi
                
                import_db ${LOCATION}
                return $?
              ;;
          *)
                echo "Не указана команда"
                return 1
  esac
}

parse_command "$@"
print_debug
execute_comand

exit $?
