# Shared helpers for Phase 2 verification scripts. SOURCE this file; do not execute it.
# psql exit codes: 0 ok; 1 fatal; 2 connection/environment failure; 3 ON_ERROR_STOP script error (DDL or test).
classify(){ case "$1" in 0) echo OK;; 2) echo ENVIRONMENT;; 3) echo SCRIPT_OR_TEST_ERROR;; *) echo FATAL_OR_OTHER;; esac; }

# req LABEL CMD...  : run CMD; if it fails, print a classified diagnostic and return its code.
req(){
  local label="$1"; shift
  "$@"; local rc=$?
  if [ $rc -ne 0 ]; then echo "REQUIRED STEP FAILED [$label] exit=$rc class=$(classify $rc)" >&2; fi
  return $rc
}

# db_fresh NAME : drop (if present) and create NAME. Failure is reported, never ignored.
db_fresh(){
  req "create-db:$1" psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $1;" -c "CREATE DATABASE $1;" >/dev/null
}

# db_drop NAME : cleanup of a database created by THIS run. Failure is reported and returned.
db_drop(){
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $1;" >/dev/null 2>/tmp/.drop_err.$$; local rc=$?
  if [ $rc -ne 0 ]; then echo "CLEANUP FAILED [drop $1] exit=$rc: $(head -1 /tmp/.drop_err.$$)" >&2; fi
  rm -f /tmp/.drop_err.$$
  return $rc
}
